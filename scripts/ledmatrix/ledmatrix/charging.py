import argparse
import math
import time
from ledmatrix import Matrix, ROWS, COLS, PRIO_SYSTEM, claim

_BODY_BRIGHTNESS = 180


def _battery_pct():
    for path in ["/sys/class/power_supply/BAT1/capacity",
                 "/sys/class/power_supply/BAT0/capacity"]:
        try:
            return max(0, min(100, int(open(path).read().strip())))
        except (OSError, ValueError):
            pass
    return 50


def _bar_height(pct):
    return round(pct / 100 * ROWS)


def _build_bar(bar_h):
    m = Matrix()
    if bar_h <= 0:
        return m
    bar_top = ROWS - bar_h
    for r in range(bar_top + 1, ROWS):
        for c in range(COLS):
            m.set(r, c, _BODY_BRIGHTNESS)
    for c in range(COLS):
        m.set(bar_top, c, 255)
    return m


def _wave_fill(peak, bar_h, sigma=5.5):
    """Wave moving upward (peak decreasing), bounded to the battery fill area.
    After the wave passes a row it reveals bar brightness; above bar_top stays dark."""
    m = Matrix()
    bar_top = ROWS - bar_h if bar_h > 0 else ROWS
    for r in range(ROWS):
        if r < bar_top:
            continue  # above fill line: always dark
        wave_b = int(255 * math.exp(-((r - peak) ** 2) / (2 * sigma ** 2)))
        if peak < r:
            floor_b = _BODY_BRIGHTNESS if r > bar_top else 255
            b = max(wave_b, floor_b)
        else:
            b = wave_b
        if b > 0:
            for c in range(COLS):
                m.set(r, c, b)
    return m


def _wave_erase(peak, bar_h, sigma=5.5):
    """Wave moving downward (peak increasing). Rows the wave has already swept
    through are dark; rows ahead still show bar brightness. Nothing above
    bar_top is ever lit."""
    m = Matrix()
    bar_top = ROWS - bar_h if bar_h > 0 else ROWS
    for r in range(ROWS):
        if r < bar_top:
            continue  # above fill line: always dark
        wave_b = int(255 * math.exp(-((r - peak) ** 2) / (2 * sigma ** 2)))
        if peak > r:
            # wave has swept past — erased, just the fading tail
            b = wave_b
        else:
            # still intact — show bar
            floor_b = _BODY_BRIGHTNESS if r > bar_top else 255
            b = max(wave_b, floor_b)
        if b > 0:
            for c in range(COLS):
                m.set(r, c, b)
    return m


def _fade_bar(dev, bar_h):
    for s in [0.75, 0.5, 0.28, 0.12, 0.03, 0.0]:
        m = _build_bar(bar_h)
        for r in range(ROWS):
            for c in range(COLS):
                v = m.get(r, c)
                if v:
                    m.set(r, c, round(v * s))
        m.send(dev)
        time.sleep(0.055)


def _plug(dev, pct):
    bar_h = _bar_height(pct)
    bar_top = ROWS - bar_h if bar_h > 0 else ROWS

    # Start dark — wave reveals the bar as it rises
    # Peak travels from below screen to just past the fill line
    for peak in range(ROWS + 5, bar_top - 1, -2):
        _wave_fill(peak, bar_h).send(dev)
        time.sleep(0.032)

    # Double pulse to confirm charge connected
    for s in [0.55, 1.0, 0.55, 1.0]:
        m = _build_bar(bar_h)
        for r in range(ROWS):
            for c in range(COLS):
                v = m.get(r, c)
                if v:
                    m.set(r, c, round(v * s))
        m.send(dev)
        time.sleep(0.06)
    _build_bar(bar_h).send(dev)
    time.sleep(0.5)
    _fade_bar(dev, bar_h)


def _unplug(dev, pct):
    bar_h = _bar_height(pct)
    bar_top = ROWS - bar_h if bar_h > 0 else ROWS

    # Brief soft dim before the wave — feels like the connection flickering off
    _build_bar(bar_h).send(dev)
    time.sleep(0.12)
    for s in [0.45, 0.15, 0.45, 1.0]:
        m = _build_bar(bar_h)
        for r in range(ROWS):
            for c in range(COLS):
                v = m.get(r, c)
                if v:
                    m.set(r, c, round(v * s))
        m.send(dev)
        time.sleep(0.05)

    # Wave erases from fill line downward to the bottom
    for peak in range(bar_top - 5, ROWS + 5, 2):
        _wave_erase(peak, bar_h).send(dev)
        time.sleep(0.032)

    Matrix().send(dev)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["plug", "unplug"])
    parser.add_argument("--battery", type=int, default=None,
                        help="battery percentage (0-100); auto-read if omitted")
    parser.add_argument("--dev", default="/dev/ttyACM0")
    args = parser.parse_args()

    pct = args.battery if args.battery is not None else _battery_pct()

    with claim(PRIO_SYSTEM) as acquired:
        if not acquired:
            return
        if args.action == "plug":
            _plug(args.dev, pct)
        else:
            _unplug(args.dev, pct)
