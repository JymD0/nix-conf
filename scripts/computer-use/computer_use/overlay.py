import json
import math
import os
import socket
import threading
import time

import cairo
import gi
gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, GLib, Gtk, Gtk4LayerShell

SOCK_PATH = "/tmp/computer-use-overlay.sock"
LOCK_PATH = "/tmp/computer-use-stopped"

# dracula palette
PURPLE = (0.74, 0.58, 0.98)    # bd93f9
CYAN = (0.55, 0.91, 0.99)      # 8be9fd
RED = (1.0, 0.33, 0.33)        # ff5555
GREEN = (0.31, 0.98, 0.48)     # 50fa7b
BG = (0.16, 0.16, 0.21)        # 282a36
FG = (0.97, 0.97, 0.95)        # f8f8f2

GLOW_THICKNESS = 3
GLOW_FADE = 18
RIPPLE_DURATION_MS = 500
RIPPLE_MAX_RADIUS = 24
PULSE_PERIOD = 2.0
FADE_DURATION = 0.3


class Ripple:
    def __init__(self, x, y):
        self.x = x
        self.y = y
        self.birth = time.monotonic()

    @property
    def progress(self):
        return min((time.monotonic() - self.birth) * 1000 / RIPPLE_DURATION_MS, 1.0)

    @property
    def alive(self):
        return self.progress < 1.0


class GlowWindow(Gtk.ApplicationWindow):
    """Fullscreen transparent overlay with empty input region (click-through).
    Draws a border glow around the screen edges and click ripples."""

    def __init__(self, app, gdk_monitor):
        super().__init__(application=app)
        self.gdk_monitor = gdk_monitor

        Gtk4LayerShell.init_for_window(self)
        Gtk4LayerShell.set_layer(self, Gtk4LayerShell.Layer.OVERLAY)
        Gtk4LayerShell.set_keyboard_mode(self, Gtk4LayerShell.KeyboardMode.NONE)
        Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.TOP, True)
        Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.BOTTOM, True)
        Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.LEFT, True)
        Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.RIGHT, True)
        Gtk4LayerShell.set_exclusive_zone(self, -1)
        Gtk4LayerShell.set_monitor(self, gdk_monitor)

        css = Gtk.CssProvider()
        css.load_from_string("window { background: transparent; }")
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        self.active = False
        self.ripples = []
        # fade: 0.0 = invisible, 1.0 = fully visible
        self._fade = 0.0
        self._fade_target = 0.0

        da = Gtk.DrawingArea()
        da.set_draw_func(self._draw)
        self.set_child(da)
        self._da = da

        # make fully click-through
        self.connect("realize", self._on_realize)

        self._tick_id = GLib.timeout_add(16, self._tick)

    def _on_realize(self, w):
        surface = self.get_surface()
        if hasattr(surface, "set_input_region"):
            surface.set_input_region(cairo.Region())

    def _tick(self):
        self.ripples = [r for r in self.ripples if r.alive]

        # animate fade
        target = 1.0 if self.active else 0.0
        if self._fade != target:
            step = 16.0 / (FADE_DURATION * 1000)
            if target > self._fade:
                self._fade = min(self._fade + step, 1.0)
            else:
                self._fade = max(self._fade - step, 0.0)

        if self._fade > 0.001 or self.ripples:
            self._da.queue_draw()
        return True

    def _draw(self, area, cr, width, height):
        cr.set_operator(0)
        cr.paint()
        cr.set_operator(2)

        if self._fade > 0:
            self._draw_glow(cr, width, height)

        for ripple in self.ripples:
            self._draw_ripple(cr, ripple)

    def _draw_glow(self, cr, w, h):
        color = PURPLE
        t = time.monotonic() % PULSE_PERIOD / PULSE_PERIOD
        pulse = 0.4 + 0.25 * math.sin(t * 2 * math.pi)

        total = GLOW_THICKNESS + GLOW_FADE
        corner_r = 14

        # clip to a border frame: full surface minus a rounded inner rect
        # this gives sharp outer corners and rounded inner corners
        cr.save()
        inset = total
        ix0, iy0 = inset, inset
        ix1, iy1 = w - inset, h - inset
        r = corner_r
        # outer path (full surface, clockwise)
        cr.rectangle(0, 0, w, h)
        # inner path (rounded rect, counter-clockwise to subtract)
        cr.new_sub_path()
        cr.arc_negative(ix0 + r, iy0 + r, r, 3 * math.pi / 2, math.pi)
        cr.arc_negative(ix0 + r, iy1 - r, r, math.pi, math.pi / 2)
        cr.arc_negative(ix1 - r, iy1 - r, r, math.pi / 2, 0)
        cr.arc_negative(ix1 - r, iy0 + r, r, 0, -math.pi / 2)
        cr.close_path()
        cr.clip()

        # draw sharp concentric rectangles (clipped to the rounded frame)
        for i in range(total):
            if i < GLOW_THICKNESS:
                alpha = pulse
            else:
                alpha = pulse * (1.0 - (i - GLOW_THICKNESS) / GLOW_FADE)
            alpha *= self._fade
            cr.set_source_rgba(*color, alpha)
            cr.set_line_width(1)
            cr.rectangle(i + 0.5, i + 0.5, w - 2 * i - 1, h - 2 * i - 1)
            cr.stroke()

        cr.restore()

    def _draw_ripple(self, cr, ripple):
        p = ripple.progress
        ep = 1.0 - (1.0 - p) ** 3
        radius = RIPPLE_MAX_RADIUS * ep
        alpha = (1.0 - p) * 0.8

        cr.set_source_rgba(*CYAN, alpha)
        cr.set_line_width(2)
        cr.arc(ripple.x, ripple.y, radius, 0, 2 * math.pi)
        cr.stroke()

        cr.set_source_rgba(*CYAN, alpha * 0.5)
        cr.arc(ripple.x, ripple.y, 3, 0, 2 * math.pi)
        cr.fill()


class BadgeWindow(Gtk.ApplicationWindow):
    """Tiny status pill matching waybar's floating style."""

    def __init__(self, app, on_stop=None):
        super().__init__(application=app)
        self._on_stop = on_stop

        Gtk4LayerShell.init_for_window(self)
        Gtk4LayerShell.set_layer(self, Gtk4LayerShell.Layer.OVERLAY)
        Gtk4LayerShell.set_keyboard_mode(self, Gtk4LayerShell.KeyboardMode.NONE)
        Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.BOTTOM, True)
        Gtk4LayerShell.set_margin(self, Gtk4LayerShell.Edge.BOTTOM, 60)
        Gtk4LayerShell.set_exclusive_zone(self, -1)

        self.set_default_size(220, 36)
        self.badge_visible = False
        self._fade = 0.0

        css = Gtk.CssProvider()
        css.load_from_string("window { background: transparent; }")
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        da = Gtk.DrawingArea()
        da.set_draw_func(self._draw)
        da.set_content_width(220)
        da.set_content_height(36)
        self.set_child(da)
        self._da = da

        click = Gtk.GestureClick()
        click.connect("pressed", self._on_click)
        da.add_controller(click)

        self._tick_id = GLib.timeout_add(16, self._badge_tick)

    def _badge_tick(self):
        target = 1.0 if self.badge_visible else 0.0
        if self._fade != target:
            step = 16.0 / (FADE_DURATION * 1000)
            if target > self._fade:
                self._fade = min(self._fade + step, 1.0)
            else:
                self._fade = max(self._fade - step, 0.0)
            self._da.queue_draw()
        return True

    def _draw(self, area, cr, width, height):
        cr.set_operator(0)
        cr.paint()
        cr.set_operator(2)

        if self._fade <= 0:
            return

        r = height / 2
        accent = PURPLE
        fade = self._fade

        # pill background
        cr.new_sub_path()
        cr.arc(r, r, r - 1, math.pi / 2, 3 * math.pi / 2)
        cr.arc(width - r, r, r - 1, 3 * math.pi / 2, math.pi / 2)
        cr.close_path()
        cr.set_source_rgba(*BG, 0.9 * fade)
        cr.fill_preserve()
        cr.set_source_rgba(*accent, 0.5 * fade)
        cr.set_line_width(1)
        cr.stroke()

        # status dot
        dot_x = 16
        dot_y = height / 2
        cr.arc(dot_x, dot_y, 4, 0, 2 * math.pi)
        cr.set_source_rgba(*accent, 1.0 * fade)
        cr.fill()

        # label
        cr.select_font_face("monospace", 0, 0)
        cr.set_font_size(13)
        cy = height / 2 + 4.5

        cr.set_source_rgba(*FG, 0.8 * fade)
        cr.move_to(28, cy)
        cr.show_text("Computer Use")
        # close button
        cr.set_source_rgba(*FG, 0.4 * fade)
        cr.set_font_size(15)
        ext = cr.text_extents("\u00d7")
        cr.move_to(width - ext.width - 12, cy + 1)
        cr.show_text("\u00d7")
        self._btn_x = width - ext.width - 16

    def _on_click(self, gesture, n_press, x, y):
        if not self.badge_visible:
            return
        if hasattr(self, "_btn_x") and x >= self._btn_x - 4:
            self._end_session()

    def _end_session(self):
        with open(LOCK_PATH, "w") as f:
            f.write("1")
        self.badge_visible = False
        self._da.queue_draw()
        if self._on_stop:
            self._on_stop()

    def show(self):
        self.badge_visible = True
        self._da.queue_draw()

    def hide(self):
        self.badge_visible = False
        self._da.queue_draw()


class Overlay:
    def __init__(self):
        self.badge = None
        self.glows = {}  # connector -> GlowWindow
        self.app = None

    def _setup(self):
        display = Gdk.Display.get_default()
        monitors = display.get_monitors()
        for i in range(monitors.get_n_items()):
            mon = monitors.get_item(i)
            name = mon.get_connector() or f"monitor-{i}"
            glow = GlowWindow(self.app, mon)
            glow.present()
            self.glows[name] = glow

        self.badge = BadgeWindow(self.app, on_stop=self._deactivate_glows)
        self.badge.present()

    def _find_glow_for_coords(self, x, y):
        """Find the glow window containing these global coords, return (glow, local_x, local_y)."""
        display = Gdk.Display.get_default()
        monitors = display.get_monitors()
        for i in range(monitors.get_n_items()):
            mon = monitors.get_item(i)
            geo = mon.get_geometry()
            if geo.x <= x < geo.x + geo.width and geo.y <= y < geo.y + geo.height:
                name = mon.get_connector() or f"monitor-{i}"
                if name in self.glows:
                    return self.glows[name], x - geo.x, y - geo.y
        if self.glows:
            first = next(iter(self.glows.values()))
            return first, x, y
        return None, x, y

    def _deactivate_glows(self):
        """Called by badge stop button to turn off glow windows."""
        for glow in self.glows.values():
            glow.active = False

    def _set_active(self, active):
        for glow in self.glows.values():
            glow.active = active
        self.badge.badge_visible = active
        self.badge._da.queue_draw()

    def _end(self):
        """End session: write lock file and fade out."""
        with open(LOCK_PATH, "w") as f:
            f.write("1")
        self._set_active(False)

    def _clear_stopped(self):
        """Clear the lock file (called when starting a new session)."""
        try:
            os.remove(LOCK_PATH)
        except FileNotFoundError:
            pass

    def handle_command(self, data):
        cmd = data.get("type")

        if cmd == "ripple":
            x, y = data.get("x", 0), data.get("y", 0)
            def add_ripple():
                glow, lx, ly = self._find_glow_for_coords(x, y)
                if glow:
                    glow.ripples.append(Ripple(lx, ly))
            GLib.idle_add(add_ripple)

        elif cmd == "badge":
            GLib.idle_add(self._clear_stopped)
            GLib.idle_add(self._set_active, True)

        elif cmd == "hide":
            GLib.idle_add(self._set_active, False)

        elif cmd == "stop":
            GLib.idle_add(self._end)

        elif cmd == "ping":
            return

    def start_socket_listener(self):
        def listen():
            try:
                os.unlink(SOCK_PATH)
            except FileNotFoundError:
                pass

            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.bind(SOCK_PATH)
            os.chmod(SOCK_PATH, 0o600)
            sock.listen(5)

            while True:
                conn, _ = sock.accept()
                try:
                    buf = b""
                    while True:
                        chunk = conn.recv(4096)
                        if not chunk:
                            break
                        buf += chunk
                    if buf:
                        data = json.loads(buf.decode())
                        self.handle_command(data)
                except Exception:
                    pass
                finally:
                    conn.close()

        t = threading.Thread(target=listen, daemon=True)
        t.start()

    def run(self):
        self.app = Gtk.Application(application_id="com.computer-use.overlay")

        def on_activate(app):
            self._setup()
            self.start_socket_listener()

        self.app.connect("activate", on_activate)
        self.app.run(None)


def main():
    import atexit

    def cleanup():
        try:
            os.unlink(SOCK_PATH)
        except FileNotFoundError:
            pass

    atexit.register(cleanup)
    overlay = Overlay()
    overlay.run()


if __name__ == "__main__":
    main()
