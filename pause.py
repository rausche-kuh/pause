#!/usr/bin/env python3
"""Pause: full-screen eye breaks and walking-pad prompts.

  pause.py run           background loop (started by pause.service)
  pause.py show eye      show an eye break now
  pause.py show walk 1   show walking-pad prompt 1 now
  pause.py test          self-check of the scheduling logic
"""
import os
import subprocess
import sys
import time
import traceback
from datetime import date, datetime, time as clock, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOG = HERE / "log"

WORKDAYS = range(5)  # Mon–Fri
WORK_HOURS = (clock(7, 0), clock(16, 30))
EYE_EVERY = 45  # minutes of unlocked screen time between eye breaks
EYE_SECONDS = 30
WALKS = {1: clock(9, 30), 2: clock(14, 30)}
SETUP_SECONDS = 20  # walk button unlocks after the pad is set up
LATER = timedelta(minutes=10)
PROMPT_TIMEOUT = 20 * 60  # seconds; an unanswered prompt is closed and asked again later

RESULTS = {0: "done", 1: "start", 2: "later", 3: "skip"}  # UI exit codes

SOUNDS = Path("/usr/share/sounds/ocean/stereo")  # Plasma's sound theme
SOUND_SHOW = "desktop-login"
SOUND_AFTER = {0: "completion-success", 1: "outcome-success"}  # eye break over, walk started
SOUND_VOLUME = 0.7


def read_log():
    try:
        lines = [line.split() for line in LOG.read_text().splitlines()]
    except FileNotFoundError:
        return []
    return [parts for parts in lines if len(parts) == 3]


def answered_walks():
    return {(datetime.fromisoformat(ts).date(), int(what[4:]))
            for ts, what, result in read_log()
            if what.startswith("walk") and result in ("start", "skip")}


def snooze_from_log():
    """When the last unanswered walk prompt may come back, so restarts keep a snooze."""
    asked = [datetime.fromisoformat(ts) for ts, what, result in read_log()
             if what.startswith("walk") and result not in ("start", "skip")]
    return max(asked) + LATER if asked else None


def walked_this_week(today: date):
    monday = today - timedelta(days=today.weekday())
    walked = {datetime.fromisoformat(ts).date()
              for ts, what, result in read_log()
              if what.startswith("walk") and result == "start"}
    return [monday + timedelta(days=d) in walked for d in range(5)]


def walk_due(now: datetime, answered, snoozed_until):
    """Latest walk whose time has passed today, unless answered or snoozed."""
    passed = [n for n, t in WALKS.items() if now.time() >= t]
    if not passed or (now.date(), max(passed)) in answered:
        return None
    if snoozed_until and now < snoozed_until:
        return None
    return max(passed)


def locked():
    r = subprocess.run(["qdbus6", "org.freedesktop.ScreenSaver", "/ScreenSaver",
                        "org.freedesktop.ScreenSaver.GetActive"],
                       capture_output=True, text=True)
    return r.stdout.strip() == "true"


def show(kind, n=0):
    try:
        code = subprocess.run([sys.executable, __file__, "show", kind, str(n)],
                              timeout=PROMPT_TIMEOUT).returncode
        result = RESULTS.get(code, "error")
    except subprocess.TimeoutExpired:  # unanswered, or never appeared: don't block the loop
        result = "timeout"
    with LOG.open("a") as f:
        f.write(f"{datetime.now():%Y-%m-%dT%H:%M:%S} {kind}{n or ''} {result}\n")
    return result


def run():
    # Locked screen = away. KDE auto-locks after 5 idle minutes, which resets the count.
    active, snoozed, answered = 0, snooze_from_log(), answered_walks()
    while True:
        time.sleep(60)
        now = datetime.now()
        if locked():
            active = 0
            continue
        active += 1
        if now.weekday() not in WORKDAYS or not WORK_HOURS[0] <= now.time() < WORK_HOURS[1]:
            continue
        if n := walk_due(now, answered, snoozed):
            if show("walk", n) in ("start", "skip"):
                answered.add((now.date(), n))
            else:  # "later", or the UI failed: ask again in 10 min
                snoozed = datetime.now() + LATER  # from the answer, not from when it was shown
        elif active >= EYE_EVERY:
            show("eye")
            active = 0


def chime(name):
    try:
        subprocess.Popen(["paplay", f"--volume={int(SOUND_VOLUME * 65536)}", SOUNDS / f"{name}.oga"],
                         stderr=subprocess.DEVNULL)
    except OSError:
        pass  # no sound is fine


def screenshot():
    """Snapshot of all screens for the blurred backdrop, or None."""
    from PySide6.QtGui import QImage
    path = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "pause-shot.png"
    try:
        subprocess.run(["spectacle", "-b", "-n", "-f", "-o", str(path)],
                       capture_output=True, timeout=10, check=True)
        img = QImage(str(path))
    except (subprocess.SubprocessError, OSError):
        return None
    finally:
        path.unlink(missing_ok=True)
    return None if img.isNull() else img


def ui(kind, n):
    from PySide6.QtCore import QRect, QTimer, QUrl
    from PySide6.QtGui import QGuiApplication, QImage
    from PySide6.QtQml import QQmlApplicationEngine
    from PySide6.QtQuick import QQuickImageProvider

    app = QGuiApplication(sys.argv[:1])
    shot = screenshot()
    crops = {}
    if shot:
        # The snapshot covers the whole virtual desktop at one uniform scale.
        virtual = QRect()
        for s in app.screens():
            virtual = virtual.united(s.geometry())
        k = shot.width() / virtual.width()
        for s in app.screens():
            g = s.geometry().translated(-virtual.topLeft())
            crops[s.name()] = shot.copy(QRect(round(g.x() * k), round(g.y() * k),
                                              round(g.width() * k), round(g.height() * k)))

    class Shots(QQuickImageProvider):
        def __init__(self):
            super().__init__(QQuickImageProvider.ImageType.Image)

        def requestImage(self, name, size, requested):
            return crops.get(name, QImage())

    engine = QQmlApplicationEngine()
    engine.addImageProvider("shot", Shots())
    engine.setInitialProperties({"kind": kind, "session": n, "seconds": EYE_SECONDS if kind == "eye" else SETUP_SECONDS,
                                 "week": walked_this_week(date.today())})
    engine.load(QUrl.fromLocalFile(str(HERE / "pause.qml")))
    if not engine.rootObjects():
        sys.exit(9)
    # KWin ignores a screen set from QML; it has to be set before the window is shown.
    def place():
        screens = {s.name(): s for s in app.screens()}
        for w in app.topLevelWindows():
            s = screens.get(w.property("screenName"))
            if s and not w.isVisible():
                w.setScreen(s)
                w.setGeometry(s.geometry())
                w.showFullScreen()
                if s == app.primaryScreen():
                    w.requestActivate()
    place()
    # Waking monitors reconnect, and the Instantiator then rebuilds the windows hidden.
    app.screenAdded.connect(lambda _: QTimer.singleShot(500, place))
    app.screenRemoved.connect(lambda _: QTimer.singleShot(500, place))
    chime(SOUND_SHOW)
    code = app.exec()
    if code in SOUND_AFTER:
        chime(SOUND_AFTER[code])
    sys.exit(code)


def test():
    t = lambda h, m: datetime(2026, 10, 14, h, m)
    d = date(2026, 10, 14)
    assert walk_due(t(9, 0), set(), None) is None
    assert walk_due(t(9, 30), set(), None) == 1
    assert walk_due(t(9, 35), {(d, 1)}, None) is None
    assert walk_due(t(9, 35), set(), t(9, 40)) is None
    assert walk_due(t(9, 40), set(), t(9, 40)) == 1
    assert walk_due(t(14, 30), {(d, 1)}, None) == 2
    assert walk_due(t(15, 0), set(), None) == 2  # late start: only the latest walk
    print("ok")


if __name__ == "__main__":
    match sys.argv[1:]:
        case ["run"]: run()
        case ["show", kind, *n]:
            try:
                ui(kind, int(n[0]) if n else 0)
            except Exception:  # a crash would exit 1, which means "start"
                traceback.print_exc()
                sys.exit(9)
        case ["test"]: test()
        case _: sys.exit(__doc__)
