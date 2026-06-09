import base64
import io
import json
import os
import socket
import subprocess
import time

from PIL import Image, ImageDraw

from mcp.server.fastmcp import FastMCP
from mcp.types import ImageContent, TextContent

mcp = FastMCP("computer-use")

# max dimensions for screenshots sent to Claude (within 1568px / 1.15MP limit)
MAX_WIDTH = 1280
MAX_HEIGHT = 800

SOCK_PATH = "/tmp/computer-use-overlay.sock"
LOCK_PATH = "/tmp/computer-use-stopped"
SESSION_LOCK = "/tmp/computer-use-session.lock"

# overlay process ref so we can clean up
_overlay_proc = None


# overlay helpers

def _ensure_overlay():
    """Start the overlay daemon if it's not already running."""
    global _overlay_proc
    if _overlay_proc and _overlay_proc.poll() is None:
        return
    # check if another instance is already listening
    if os.path.exists(SOCK_PATH):
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(0.5)
            sock.connect(SOCK_PATH)
            sock.sendall(b'{"type":"ping"}')
            sock.close()
            return
        except Exception:
            # stale socket, clean up and restart
            try:
                os.unlink(SOCK_PATH)
            except FileNotFoundError:
                pass
    _overlay_proc = subprocess.Popen(
        ["computer-use-overlay"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    # wait for the overlay to create and start listening on its socket
    # GTK4 + layer-shell init can take a few seconds
    for _ in range(60):
        if os.path.exists(SOCK_PATH):
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.settimeout(0.3)
                s.connect(SOCK_PATH)
                s.sendall(b'{"type":"ping"}')
                s.close()
                return
            except Exception:
                pass
        time.sleep(0.1)


def _overlay_send(data):
    """Send a command to the overlay daemon."""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(0.5)
        sock.connect(SOCK_PATH)
        sock.sendall(json.dumps(data).encode())
        sock.close()
    except Exception:
        pass


_session_active = False


def _notify_ripple(x, y):
    """Show a click ripple at native screen coords."""
    _overlay_send({"type": "ripple", "x": x, "y": y})


def _require_session():
    """Raise if no session is active or the user ended it."""
    if os.path.exists(LOCK_PATH):
        global _session_active
        _session_active = False
        raise RuntimeError(
            "The user ended the computer use session. "
            "Do not start a new session without asking the user first."
        )
    if not _session_active:
        raise RuntimeError(
            "No active computer use session. "
            "Call start_session() first."
        )


# helpers

def _run(cmd, check=True, text=True):
    """Run a shell command, return CompletedProcess."""
    return subprocess.run(cmd, capture_output=True, check=check, text=text)


def _run_bytes(cmd):
    """Run a shell command that produces binary stdout (e.g. grim)."""
    return subprocess.run(cmd, capture_output=True, check=True).stdout


def _run_json(cmd):
    """Run a command and parse stdout as JSON."""
    result = _run(cmd)
    return json.loads(result.stdout)


def _monitors():
    """Get all monitor info from hyprctl."""
    return _run_json(["hyprctl", "monitors", "-j"])


def _focused_monitor():
    """Find the currently focused monitor."""
    mons = _monitors()
    if not mons:
        raise RuntimeError("no monitors reported by hyprctl")
    for m in mons:
        if m.get("focused"):
            return m
    return mons[0]


def _find_monitor(name=None):
    """Find a monitor by name, or return the focused one."""
    if not name:
        return _focused_monitor()
    for m in _monitors():
        if m["name"] == name:
            return m
    raise ValueError(f"Monitor '{name}' not found")


def _cursor_pos():
    """Get current cursor position as (x, y)."""
    pos = _run_json(["hyprctl", "cursorpos", "-j"])
    return pos["x"], pos["y"]


def _downscale(img):
    """Downscale image to fit within MAX_WIDTH x MAX_HEIGHT, preserving aspect ratio.
    Returns (scaled_image, scale_factor)."""
    w, h = img.size
    scale = min(MAX_WIDTH / w, MAX_HEIGHT / h, 1.0)
    if scale < 1.0:
        new_w = int(w * scale)
        new_h = int(h * scale)
        return img.resize((new_w, new_h), Image.LANCZOS), scale
    return img, 1.0


def _draw_cursor(img, x, y):
    """Draw a red crosshair at (x, y) on the image."""
    draw = ImageDraw.Draw(img)
    arm = 20
    width = 2
    color = (255, 0, 0)
    draw.line([(x - arm, y), (x + arm, y)], fill=color, width=width)
    draw.line([(x, y - arm), (x, y + arm)], fill=color, width=width)


def _capture(geometry=None, output=None):
    """Capture a screenshot with grim. Returns PIL Image.
    geometry: "x,y widthxheight" string for region capture
    output: monitor name for single-output capture"""
    cmd = ["grim"]
    if output:
        cmd += ["-o", output]
    if geometry:
        cmd += ["-g", geometry]
    cmd.append("-")
    data = _run_bytes(cmd)
    return Image.open(io.BytesIO(data))


def _screenshot_response(img, native_w, native_h, offset_x=0, offset_y=0, monitor_name=None):
    """Build a standard screenshot response with base64 image + metadata."""
    scaled, _ = _downscale(img)
    buf = io.BytesIO()
    scaled.save(buf, format="PNG", optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode()

    meta = {
        "image_width": scaled.size[0],
        "image_height": scaled.size[1],
        "native_width": native_w,
        "native_height": native_h,
        "offset_x": offset_x,
        "offset_y": offset_y,
    }
    if monitor_name:
        meta["monitor"] = monitor_name

    return [
        TextContent(type="text", text=json.dumps(meta)),
        ImageContent(type="image", data=b64, mimeType="image/png"),
    ]


def _scale_to_native(api_x, api_y, image_w, image_h, native_w, native_h, offset_x=0, offset_y=0):
    """Convert screenshot-space coords to absolute screen coords."""
    screen_x = int(api_x * (native_w / image_w)) + offset_x
    screen_y = int(api_y * (native_h / image_h)) + offset_y
    return screen_x, screen_y


def _move_cursor(x, y):
    """Move the cursor to absolute screen coordinates via ydotool.
    Uses ydotool instead of hyprctl so the cursor stays visible
    (hyprctl movecursor warps without generating input events,
    which causes the software cursor to not redraw).
    Requires the ydotool device to have accel_profile=flat in Hyprland."""
    _run(["ydotool", "mousemove", "--absolute", "-x", str(x), "-y", str(y)])


def _ydotool_click(button=0xC0, repeat=1, delay=50):
    """Click using ydotool. 0xC0=left, 0xC1=right, 0xC2=middle."""
    cmd = ["ydotool", "click", f"0x{button:02X}"]
    if repeat > 1:
        cmd += ["-r", str(repeat), "-D", str(delay)]
    _run(cmd)


def _move_and_click(x, y, button=0xC0, repeat=1):
    """Move cursor via hyprctl (reliable on Wayland) then click via ydotool.
    hyprctl dispatch is synchronous over IPC, so no race condition."""
    _move_cursor(x, y)
    _ydotool_click(button, repeat=repeat)


# session tools

def _session_lock_held():
    """Check if another process holds the session lock."""
    try:
        with open(SESSION_LOCK) as f:
            pid = int(f.read().strip())
        # check if that process is still alive
        os.kill(pid, 0)
        return pid
    except (FileNotFoundError, ValueError, ProcessLookupError, PermissionError):
        return None


def _acquire_session_lock():
    """Try to acquire the session lock. Returns True on success."""
    holder = _session_lock_held()
    if holder and holder != os.getpid():
        return False
    with open(SESSION_LOCK, "w") as f:
        f.write(str(os.getpid()))
    return True


def _release_session_lock():
    """Release the session lock if we own it."""
    try:
        with open(SESSION_LOCK) as f:
            pid = int(f.read().strip())
        if pid == os.getpid():
            os.remove(SESSION_LOCK)
    except (FileNotFoundError, ValueError):
        pass


@mcp.tool()
def start_session() -> str:
    """Start a computer use session. This activates the screen overlay so the
    user knows you're controlling their computer. You MUST call this before
    using any other computer use tools. The user can end the session at any
    time via keybind or the overlay button."""
    global _session_active
    if not _acquire_session_lock():
        holder = _session_lock_held()
        raise RuntimeError(
            f"Another computer use session is already active (PID {holder}). "
            "Only one session can run at a time."
        )
    if os.path.exists(LOCK_PATH):
        try:
            os.remove(LOCK_PATH)
        except FileNotFoundError:
            pass
    _ensure_overlay()
    _overlay_send({"type": "badge"})
    _session_active = True
    return "Session started. The overlay is now visible to the user."


@mcp.tool()
def end_session() -> str:
    """End the computer use session. Call this when you're done interacting
    with the screen. The overlay will be hidden."""
    global _session_active
    _session_active = False
    _release_session_lock()
    _overlay_send({"type": "hide"})
    return "Session ended."


# screenshot tools

@mcp.tool()
def screenshot(monitor: str | None = None) -> list:
    """Take a screenshot of an entire monitor.
    The image includes a red crosshair at the current cursor position.
    Returns the image with metadata including dimensions and monitor offset
    for coordinate mapping. Pass coordinates from this screenshot to click().

    Args:
        monitor: Monitor name (e.g. "eDP-1"). Defaults to the focused monitor.
    """
    _require_session()
    mon = _find_monitor(monitor)
    img = _capture(output=mon["name"])
    cx, cy = _cursor_pos()
    # cursor pos is in global layout space, make it relative to this monitor
    rel_cx = cx - mon["x"]
    rel_cy = cy - mon["y"]
    # draw cursor on the native image before downscaling
    if 0 <= rel_cx < img.size[0] and 0 <= rel_cy < img.size[1]:
        _draw_cursor(img, rel_cx, rel_cy)
    return _screenshot_response(
        img, img.size[0], img.size[1],
        offset_x=mon["x"], offset_y=mon["y"],
        monitor_name=mon["name"],
    )


@mcp.tool()
def screenshot_window(class_name: str | None = None, title: str | None = None) -> list:
    """Take a screenshot of a specific window by its class or title.
    Higher resolution than a full monitor screenshot since only the window
    region is captured. The image includes a red crosshair at the cursor.

    Args:
        class_name: Window class to match (e.g. "kitty", "firefox"). Case-insensitive substring match.
        title: Window title to match. Case-insensitive substring match.
    """
    _require_session()
    if not class_name and not title:
        raise ValueError("Provide class_name or title to identify the window")

    clients = _run_json(["hyprctl", "clients", "-j"])
    match = None
    for c in clients:
        if class_name and class_name.lower() not in c.get("class", "").lower():
            continue
        if title and title.lower() not in c.get("title", "").lower():
            continue
        match = c
        break

    if not match:
        raise ValueError(f"No window found matching class='{class_name}' title='{title}'")

    wx, wy = match["at"]
    ww, wh = match["size"]
    geometry = f"{wx},{wy} {ww}x{wh}"
    img = _capture(geometry=geometry)

    cx, cy = _cursor_pos()
    rel_cx = cx - wx
    rel_cy = cy - wy
    if 0 <= rel_cx < img.size[0] and 0 <= rel_cy < img.size[1]:
        _draw_cursor(img, rel_cx, rel_cy)

    return _screenshot_response(img, ww, wh, offset_x=wx, offset_y=wy)


@mcp.tool()
def screenshot_region(x: int, y: int, width: int, height: int) -> list:
    """Take a screenshot of a specific screen region. Useful for zooming in
    on an area identified in a previous screenshot for more precise targeting.
    Coordinates are in native screen space (absolute layout coordinates).

    Args:
        x: Left edge in native screen coordinates.
        y: Top edge in native screen coordinates.
        width: Region width in pixels.
        height: Region height in pixels.
    """
    _require_session()
    geometry = f"{x},{y} {width}x{height}"
    img = _capture(geometry=geometry)

    cx, cy = _cursor_pos()
    rel_cx = cx - x
    rel_cy = cy - y
    if 0 <= rel_cx < img.size[0] and 0 <= rel_cy < img.size[1]:
        _draw_cursor(img, rel_cx, rel_cy)

    return _screenshot_response(img, width, height, offset_x=x, offset_y=y)


# context tools

@mcp.tool()
def get_windows() -> str:
    """List all open windows with their class, title, position, size, workspace, and PID."""
    clients = _run_json(["hyprctl", "clients", "-j"])
    # return only the fields that matter
    result = []
    for c in clients:
        result.append({
            "class": c.get("class", ""),
            "title": c.get("title", ""),
            "at": c.get("at"),
            "size": c.get("size"),
            "workspace": c.get("workspace", {}).get("name", ""),
            "pid": c.get("pid"),
            "focused": c.get("focusHistoryID", -1) == 0,
        })
    return json.dumps(result, indent=2)


@mcp.tool()
def get_active_window() -> str:
    """Get the currently focused window's class, title, position, and size."""
    return json.dumps(_run_json(["hyprctl", "activewindow", "-j"]), indent=2)


@mcp.tool()
def get_monitors() -> str:
    """List all monitors with name, resolution, scale, and position."""
    mons = _monitors()
    result = []
    for m in mons:
        result.append({
            "name": m["name"],
            "width": m["width"],
            "height": m["height"],
            "scale": m["scale"],
            "x": m["x"],
            "y": m["y"],
            "focused": m.get("focused", False),
        })
    return json.dumps(result, indent=2)


@mcp.tool()
def get_workspaces() -> str:
    """List all workspaces with their ID, name, monitor, and window count."""
    workspaces = _run_json(["hyprctl", "workspaces", "-j"])
    result = []
    for ws in workspaces:
        result.append({
            "id": ws.get("id"),
            "name": ws.get("name", ""),
            "monitor": ws.get("monitor", ""),
            "windows": ws.get("windows", 0),
            "lastwindow_title": ws.get("lastwindowtitle", ""),
        })
    result.sort(key=lambda w: w["id"])
    return json.dumps(result, indent=2)


@mcp.tool()
def get_cursor_position() -> str:
    """Get the current cursor position in absolute layout coordinates."""
    x, y = _cursor_pos()
    return json.dumps({"x": x, "y": y})


@mcp.tool()
def clipboard_read() -> str:
    """Read the current clipboard contents as text."""
    result = _run(["wl-paste", "--no-newline"], check=False, text=False)
    if result.returncode != 0:
        return "(clipboard empty)"
    try:
        return result.stdout.decode("utf-8")
    except UnicodeDecodeError:
        return "(clipboard contains non-text data)"


@mcp.tool()
def clipboard_write(text: str) -> str:
    """Write text to the clipboard.

    Args:
        text: The text to copy to the clipboard.
    """
    _require_session()
    # wl-copy forks a child to serve clipboard, don't capture its pipes or we hang
    subprocess.Popen(
        ["wl-copy", "--", text],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return "ok"


# window/workspace tools

@mcp.tool()
def focus_window(class_name: str | None = None, title: str | None = None) -> str:
    """Focus a window by class or title. Automatically switches to the correct
    workspace and monitor. Use get_windows() first to see what's available.

    Args:
        class_name: Window class to match (e.g. "kitty", "zen"). Case-insensitive substring.
        title: Window title to match. Case-insensitive substring.
    """
    _require_session()
    if not class_name and not title:
        raise ValueError("Provide class_name or title")

    clients = _run_json(["hyprctl", "clients", "-j"])
    for c in clients:
        if class_name and class_name.lower() not in c.get("class", "").lower():
            continue
        if title and title.lower() not in c.get("title", "").lower():
            continue
        addr = c.get("address", "")
        _run(["hyprctl", "dispatch", "focuswindow", f"address:{addr}"])
        return json.dumps({
            "focused": c.get("class", ""),
            "title": c.get("title", ""),
            "workspace": c.get("workspace", {}).get("name", ""),
        })

    return json.dumps({"error": f"No window matching class='{class_name}' title='{title}'"})


@mcp.tool()
def switch_workspace(workspace: str) -> str:
    """Switch to a workspace by name or number.

    Args:
        workspace: Workspace name or number (e.g. "1", "2", "special:magic").
    """
    _require_session()
    _run(["hyprctl", "dispatch", "workspace", workspace])
    return json.dumps({"switched_to": workspace})


@mcp.tool()
def move_window(workspace: str, class_name: str | None = None,
                title: str | None = None) -> str:
    """Move a window to a different workspace. If no class/title given, moves the active window.

    Args:
        workspace: Target workspace name or number (e.g. "2", "special:magic").
        class_name: Window class to match. If omitted, uses the active window.
        title: Window title to match. If omitted, uses the active window.
    """
    _require_session()
    if class_name or title:
        # find and focus the target window first
        clients = _run_json(["hyprctl", "clients", "-j"])
        for c in clients:
            if class_name and class_name.lower() not in c.get("class", "").lower():
                continue
            if title and title.lower() not in c.get("title", "").lower():
                continue
            addr = c.get("address", "")
            _run(["hyprctl", "dispatch", "focuswindow", f"address:{addr}"])
            break
        else:
            return json.dumps({"error": f"No window matching class='{class_name}' title='{title}'"})

    _run(["hyprctl", "dispatch", "movetoworkspace", workspace])
    return json.dumps({"moved_to": workspace})


# input tools

@mcp.tool()
def click(x: int, y: int, image_width: int, image_height: int,
          native_width: int | None = None, native_height: int | None = None,
          offset_x: int = 0, offset_y: int = 0) -> str:
    """Left-click at coordinates from a previous screenshot.
    Pass the image_width/image_height/native_width/native_height/offset_x/offset_y
    values from the screenshot metadata to ensure correct coordinate mapping.

    Args:
        x: X coordinate in the screenshot image.
        y: Y coordinate in the screenshot image.
        image_width: Width of the screenshot image (from metadata).
        image_height: Height of the screenshot image (from metadata).
        native_width: Native width before downscaling (from metadata). Defaults to image_width.
        native_height: Native height before downscaling (from metadata). Defaults to image_height.
        offset_x: Monitor/window X offset (from metadata). Defaults to 0.
        offset_y: Monitor/window Y offset (from metadata). Defaults to 0.
    """
    _require_session()
    nw = native_width or image_width
    nh = native_height or image_height
    sx, sy = _scale_to_native(x, y, image_width, image_height, nw, nh, offset_x, offset_y)
    _notify_ripple(sx, sy)
    _move_and_click(sx, sy, button=0xC0)
    return json.dumps({"clicked_at": [sx, sy]})


@mcp.tool()
def right_click(x: int, y: int, image_width: int, image_height: int,
                native_width: int | None = None, native_height: int | None = None,
                offset_x: int = 0, offset_y: int = 0) -> str:
    """Right-click at coordinates from a previous screenshot.
    Same coordinate parameters as click().

    Args:
        x: X coordinate in the screenshot image.
        y: Y coordinate in the screenshot image.
        image_width: Width of the screenshot image (from metadata).
        image_height: Height of the screenshot image (from metadata).
        native_width: Native width before downscaling (from metadata). Defaults to image_width.
        native_height: Native height before downscaling (from metadata). Defaults to image_height.
        offset_x: Monitor/window X offset (from metadata). Defaults to 0.
        offset_y: Monitor/window Y offset (from metadata). Defaults to 0.
    """
    _require_session()
    nw = native_width or image_width
    nh = native_height or image_height
    sx, sy = _scale_to_native(x, y, image_width, image_height, nw, nh, offset_x, offset_y)
    _notify_ripple(sx, sy)
    _move_and_click(sx, sy, button=0xC1)
    return json.dumps({"clicked_at": [sx, sy]})


@mcp.tool()
def double_click(x: int, y: int, image_width: int, image_height: int,
                 native_width: int | None = None, native_height: int | None = None,
                 offset_x: int = 0, offset_y: int = 0) -> str:
    """Double-click at coordinates from a previous screenshot.
    Same coordinate parameters as click().

    Args:
        x: X coordinate in the screenshot image.
        y: Y coordinate in the screenshot image.
        image_width: Width of the screenshot image (from metadata).
        image_height: Height of the screenshot image (from metadata).
        native_width: Native width before downscaling (from metadata). Defaults to image_width.
        native_height: Native height before downscaling (from metadata). Defaults to image_height.
        offset_x: Monitor/window X offset (from metadata). Defaults to 0.
        offset_y: Monitor/window Y offset (from metadata). Defaults to 0.
    """
    _require_session()
    nw = native_width or image_width
    nh = native_height or image_height
    sx, sy = _scale_to_native(x, y, image_width, image_height, nw, nh, offset_x, offset_y)
    _notify_ripple(sx, sy)
    _move_and_click(sx, sy, button=0xC0, repeat=2)
    return json.dumps({"clicked_at": [sx, sy]})


@mcp.tool()
def mouse_move(x: int, y: int, image_width: int, image_height: int,
               native_width: int | None = None, native_height: int | None = None,
               offset_x: int = 0, offset_y: int = 0) -> str:
    """Move the mouse cursor to coordinates from a previous screenshot without clicking.
    Same coordinate parameters as click().

    Args:
        x: X coordinate in the screenshot image.
        y: Y coordinate in the screenshot image.
        image_width: Width of the screenshot image (from metadata).
        image_height: Height of the screenshot image (from metadata).
        native_width: Native width before downscaling (from metadata). Defaults to image_width.
        native_height: Native height before downscaling (from metadata). Defaults to image_height.
        offset_x: Monitor/window X offset (from metadata). Defaults to 0.
        offset_y: Monitor/window Y offset (from metadata). Defaults to 0.
    """
    _require_session()
    nw = native_width or image_width
    nh = native_height or image_height
    sx, sy = _scale_to_native(x, y, image_width, image_height, nw, nh, offset_x, offset_y)
    _move_cursor(sx, sy)
    return json.dumps({"moved_to": [sx, sy]})


@mcp.tool()
def type_text(text: str) -> str:
    """Type text into the currently focused window using wtype.
    Make sure the target window is focused first (use click() on it).

    Args:
        text: The text to type.
    """
    _require_session()
    _run(["wtype", "--", text])
    return "ok"


@mcp.tool()
def key(combo: str) -> str:
    """Press a key combination. Uses wtype key names (XKB names).

    Examples: "Return", "Tab", "ctrl+c", "ctrl+shift+t", "alt+F4", "super+space"

    Modifier names: ctrl, shift, alt, logo (Super/Windows key)
    Key names: Return, Tab, BackSpace, Delete, Home, End, Left, Right, Up, Down,
               Page_Up, Page_Down, Escape, space, F1-F12, or any printable character.

    Args:
        combo: Key combination string like "ctrl+c" or "Return".
    """
    _require_session()
    parts = combo.split("+")
    key_name = parts[-1]
    modifiers = parts[:-1]

    # map common modifier names to wtype names
    mod_map = {
        "ctrl": "ctrl", "control": "ctrl",
        "shift": "shift",
        "alt": "alt",
        "super": "logo", "logo": "logo", "win": "logo", "mod": "logo",
        "altgr": "altgr",
    }

    cmd = ["wtype"]
    for mod in modifiers:
        mapped = mod_map.get(mod.lower())
        if not mapped:
            raise ValueError(f"Unknown modifier '{mod}'. Use: ctrl, shift, alt, super")
        cmd += ["-M", mapped]
    cmd += ["-k", key_name]
    # release modifiers in reverse
    for mod in reversed(modifiers):
        mapped = mod_map.get(mod.lower())
        cmd += ["-m", mapped]

    _run(cmd)
    return "ok"


@mcp.tool()
def scroll(x: int, y: int, direction: str, amount: int,
           image_width: int, image_height: int,
           native_width: int | None = None, native_height: int | None = None,
           offset_x: int = 0, offset_y: int = 0) -> str:
    """Scroll at a position from a previous screenshot.

    Args:
        x: X coordinate in the screenshot image.
        y: Y coordinate in the screenshot image.
        direction: "up" or "down".
        amount: Number of scroll steps (typically 1-10).
        image_width: Width of the screenshot image (from metadata).
        image_height: Height of the screenshot image (from metadata).
        native_width: Native width before downscaling (from metadata). Defaults to image_width.
        native_height: Native height before downscaling (from metadata). Defaults to image_height.
        offset_x: Monitor/window X offset (from metadata). Defaults to 0.
        offset_y: Monitor/window Y offset (from metadata). Defaults to 0.
    """
    _require_session()
    nw = native_width or image_width
    nh = native_height or image_height
    sx, sy = _scale_to_native(x, y, image_width, image_height, nw, nh, offset_x, offset_y)
    _notify_ripple(sx, sy)
    _move_cursor(sx, sy)

    # ydotool REL_WHEEL: positive = up, negative = down
    scroll_val = amount if direction == "up" else -amount
    _run(["ydotool", "mousemove", "-w", "--", "0", str(scroll_val)])
    return json.dumps({"scrolled_at": [sx, sy], "direction": direction, "amount": amount})


# accessibility tools

def _atspi_available():
    """Check if AT-SPI2 bindings are available."""
    try:
        import gi
        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi
        Atspi.init()
        return True
    except (ImportError, ValueError):
        return False


def _find_atspi_app(window_class=None, window_title=None):
    """Find an AT-SPI2 application matching the given window class or title."""
    import gi
    gi.require_version("Atspi", "2.0")
    from gi.repository import Atspi

    Atspi.init()
    desktop = Atspi.get_desktop(0)

    for i in range(desktop.get_child_count()):
        app = desktop.get_child_at_index(i)
        if not app:
            continue
        app_name = app.get_name() or ""

        if window_class and window_class.lower() in app_name.lower():
            return app

        # check top-level windows
        for j in range(app.get_child_count()):
            win = app.get_child_at_index(j)
            if not win:
                continue
            win_name = win.get_name() or ""
            if window_title and window_title.lower() in win_name.lower():
                return app
            if window_class and window_class.lower() in win_name.lower():
                return app

    return None


def _walk_tree(node, elements, max_elements=200):
    """Recursively walk an AT-SPI2 tree, collecting visible elements."""
    if len(elements) >= max_elements:
        return

    try:
        import gi
        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi

        name = node.get_name() or ""
        role = node.get_role_name() or ""
        states = node.get_state_set()

        visible = states.contains(Atspi.StateType.VISIBLE)
        showing = states.contains(Atspi.StateType.SHOWING)

        if not (visible and showing):
            # still recurse into containers, but don't add this node
            for i in range(node.get_child_count()):
                child = node.get_child_at_index(i)
                if child:
                    _walk_tree(child, elements, max_elements)
            return

        bbox = None
        if node.get_component_iface():
            comp = node.get_component_iface()
            # SCREEN coords are absolute, no manual offset needed
            rect = comp.get_extents(Atspi.CoordType.SCREEN)
            if rect.width > 0 and rect.height > 0:
                bbox = {
                    "x": rect.x,
                    "y": rect.y,
                    "width": rect.width,
                    "height": rect.height,
                }

        state_names = []
        for s in [Atspi.StateType.FOCUSED, Atspi.StateType.ENABLED,
                  Atspi.StateType.CHECKED, Atspi.StateType.SELECTED,
                  Atspi.StateType.EDITABLE, Atspi.StateType.EXPANDED]:
            if states.contains(s):
                state_names.append(s.value_nick)

        # only include elements that have a name or are interactive
        interactive_roles = {
            "push button", "toggle button", "check box", "radio button",
            "text", "entry", "combo box", "menu item", "link", "tab",
            "slider", "spin button", "list item", "tree item",
        }
        if name or role in interactive_roles:
            elements.append({
                "name": name,
                "role": role,
                "states": state_names,
                "bbox": bbox,
            })

        for i in range(node.get_child_count()):
            child = node.get_child_at_index(i)
            if child:
                _walk_tree(child, elements, max_elements)

    except Exception:
        pass


@mcp.tool()
def get_elements(window_class: str | None = None, window_title: str | None = None) -> str:
    """Get the UI element tree for a window via the accessibility API (AT-SPI2).
    Returns interactive elements with their name, role, states, and bounding box.
    Bounding boxes are in absolute screen coordinates so they can be clicked directly.

    Works with GTK, Qt, and Electron/Chromium apps. Requires GTK_A11Y=atspi and
    QT_ACCESSIBILITY=1 environment variables to be set in the Hyprland session.
    Apps started before those vars were set won't expose their tree.

    Args:
        window_class: Window class to match (e.g. "firefox", "nautilus").
        window_title: Window title to match.
    """
    if not _atspi_available():
        return json.dumps({"error": "AT-SPI2 not available. Check that at-spi2-core is installed and GTK_A11Y=atspi is set."})

    app = _find_atspi_app(window_class, window_title)
    if not app:
        return json.dumps({"error": f"No accessible app found for class='{window_class}' title='{window_title}'", "elements": []})

    elements = []
    for i in range(app.get_child_count()):
        win = app.get_child_at_index(i)
        if win:
            _walk_tree(win, elements, max_elements=200)

    return json.dumps({"count": len(elements), "elements": elements}, indent=2)


@mcp.tool()
def find_element(name: str | None = None, role: str | None = None,
                 window_class: str | None = None, window_title: str | None = None) -> str:
    """Search for UI elements by name and/or role within a window.
    Returns matching elements with their bounding boxes for clicking.

    Args:
        name: Element name to search for (case-insensitive substring match).
        role: Element role to match (e.g. "push button", "entry", "link").
        window_class: Window class to search in.
        window_title: Window title to search in.
    """
    if not name and not role:
        raise ValueError("Provide at least a name or role to search for")

    raw = json.loads(get_elements(window_class, window_title))
    if "error" in raw and not raw.get("elements"):
        return json.dumps(raw)

    matches = []
    for el in raw.get("elements", []):
        if name and name.lower() not in (el.get("name") or "").lower():
            continue
        if role and role.lower() != (el.get("role") or "").lower():
            continue
        matches.append(el)

    return json.dumps({"count": len(matches), "elements": matches}, indent=2)


@mcp.tool()
def click_element(name: str, role: str | None = None,
                  window_class: str | None = None, window_title: str | None = None) -> str:
    """Find a UI element by name/role and click its center. No coordinate guessing needed.
    Uses the accessibility tree to locate the element precisely.

    Args:
        name: Element name to find and click (case-insensitive substring match).
        role: Element role to match (e.g. "push button", "entry").
        window_class: Window class to search in.
        window_title: Window title to search in.
    """
    _require_session()
    raw = json.loads(find_element(name, role, window_class, window_title))
    elements = raw.get("elements", [])

    if not elements:
        return json.dumps({"error": f"No element found matching name='{name}' role='{role}'"})

    el = elements[0]
    bbox = el.get("bbox")
    if not bbox:
        return json.dumps({"error": f"Element '{el['name']}' ({el['role']}) has no bounding box"})

    center_x = bbox["x"] + bbox["width"] // 2
    center_y = bbox["y"] + bbox["height"] // 2

    _notify_ripple(center_x, center_y)
    _move_and_click(center_x, center_y, button=0xC0)

    return json.dumps({
        "clicked": el["name"],
        "role": el["role"],
        "at": [center_x, center_y],
    })


def main():
    import atexit

    def _cleanup():
        global _session_active
        _session_active = False
        _release_session_lock()
        _overlay_send({"type": "hide"})
        if _overlay_proc and _overlay_proc.poll() is None:
            _overlay_proc.terminate()
        try:
            os.remove(LOCK_PATH)
        except FileNotFoundError:
            pass

    atexit.register(_cleanup)
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
