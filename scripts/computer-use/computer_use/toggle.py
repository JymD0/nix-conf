import json
import os
import socket
import subprocess

SOCK_PATH = "/tmp/computer-use-overlay.sock"
LOCK_PATH = "/tmp/computer-use-stopped"


def main():
    _send({"type": "stop"})
    _notify("Computer Use", "Session ended")


def _send(data):
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(0.5)
        sock.connect(SOCK_PATH)
        sock.sendall(json.dumps(data).encode())
        sock.close()
    except Exception:
        pass


def _notify(app, msg):
    try:
        subprocess.run(
            ["notify-send", "-a", app, msg],
            capture_output=True, timeout=2,
        )
    except Exception:
        pass


if __name__ == "__main__":
    main()
