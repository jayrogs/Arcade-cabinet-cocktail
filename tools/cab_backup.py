"""Copies everything on the cabinet worth keeping onto this PC, so a dead memory card is a
restore and not a rebuild.

    pythonw cab_backup.py            (does nothing if the last backup is under a day old)
    pythonw cab_backup.py --now      (backs up regardless)

Windows runs it every hour; it backs up once a day, whenever both machines happen to be on.
Only what changed since last time is copied. A file that changed or vanished on the cabinet
is not thrown away here: the old copy goes to old/<date>/ and is kept for 30 days, so a
file that goes bad on the cabinet cannot quietly replace the good copy.

What it keeps (see RESTORE.txt in the backup folder for putting it back):
    home/       the whole home folder: games, settings, Crossy Road, the shelf, the phone page
    opt/        Wine
    usr_local/  box86
    system/     /etc as one file, the boot settings, and the list of installed programs
"""
import os, sys, stat, time, shutil, datetime, posixpath

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cab

DEST = os.path.join(os.path.expanduser("~"), "Documents", "CabBackup")
# the \\?\ form lets Windows hold the very long paths inside the Wine folders
LONG = "\\\\?\\" + DEST
CURRENT = os.path.join(LONG, "current")
OLD = os.path.join(LONG, "old")
LOG = os.path.join(DEST, "backup.log")
STAMP = os.path.join(DEST, "last_ok.txt")
EVERY = 20 * 3600            # a day, with slack so the hourly check does not drift later
KEEP_DAYS = 30

HOME = "/home/jayrogs"
ROOTS = [(HOME, "home"), ("/opt", "opt"), ("/usr/local", "usr_local")]
# scratch that is big and can be made again: raw screen recordings behind the demo clips
SKIP = [HOME + "/.cache", HOME + "/demos_raw", HOME + "/flip_raw",
        HOME + "/.local/share/Trash", HOME + "/.xsession-errors"]


def log(msg):
    os.makedirs(DEST, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write("%s  %s\n" % (datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg))


def local_path(remote):
    for root, name in ROOTS:
        if remote == root or remote.startswith(root + "/"):
            rel = remote[len(root):].lstrip("/")
            # Windows cannot hold some names Linux can: keep them readable, just safe
            rel = "".join("_" if ch in '<>:"\\|?*' else ch for ch in rel)
            return os.path.join(CURRENT, name, *rel.split("/"))
    return None


def retire(path, today):
    """Move a copy out of the way rather than overwrite or delete it."""
    rel = os.path.relpath(path, CURRENT)
    dest = os.path.join(OLD, today, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    try:
        os.replace(path, dest)
    except OSError:
        shutil.copy2(path, dest)
        os.remove(path)


def remote_list(c):
    prune = " ".join("-path %s -prune -o" % cab_quote(p) for p in SKIP)
    cmd = ("find %s -xdev %s -type f -printf '%%s\\t%%T@\\t%%p\\n' 2>/dev/null"
           % (" ".join(r for r, _ in ROOTS), prune))
    i, o, e = c.exec_command(cmd, timeout=600)
    out = {}
    for line in o.read().decode("utf-8", errors="replace").splitlines():
        parts = line.split("\t", 2)
        if len(parts) == 3:
            out[parts[2]] = (int(parts[0]), int(float(parts[1])))
    return out


def cab_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"


def pull_system(c, today):
    """The system settings, as files: /etc (whatever a normal user can read, which is all
    of it except the password files), the boot settings, and the installed-program list."""
    sysdir = os.path.join(CURRENT, "system")
    os.makedirs(sysdir, exist_ok=True)
    jobs = {
        "etc.tar.gz": "tar czf - --ignore-failed-read /etc 2>/dev/null",
        "packages.txt": "dpkg --get-selections",
        "apt-manual.txt": "apt-mark showmanual",
        "boot-config.txt": "cat /boot/firmware/config.txt",
        "boot-cmdline.txt": "cat /boot/firmware/cmdline.txt",
        "user-crontab.txt": "crontab -l 2>/dev/null; true",
    }
    for name, cmd in jobs.items():
        i, o, e = c.exec_command(cmd, timeout=600)
        data = o.read()
        path = os.path.join(sysdir, name)
        if os.path.exists(path):
            with open(path, "rb") as f:
                same = f.read() == data
            if same:
                continue
            retire(path, today)
        with open(path, "wb") as f:
            f.write(data)


def prune_old():
    if not os.path.isdir(OLD):
        return
    cutoff = datetime.date.today() - datetime.timedelta(days=KEEP_DAYS)
    for name in os.listdir(OLD):
        try:
            day = datetime.date.fromisoformat(name)
        except ValueError:
            continue
        if day < cutoff:
            shutil.rmtree(os.path.join(OLD, name), ignore_errors=True)


def backup():
    today = datetime.date.today().isoformat()
    c = cab.connect()
    log("connected to %s" % c.cab_host)
    remote = remote_list(c)
    if len(remote) < 100:
        # an almost empty answer means something is wrong on that side: never let it
        # retire a good backup
        log("only %d files listed, stopping without touching the backup" % len(remote))
        c.close()
        return False
    sf = c.open_sftp()
    got = kept = failed = 0
    size = 0
    for rpath, (rsize, rtime) in remote.items():
        lp = local_path(rpath)
        if not lp:
            continue
        try:
            st = os.stat(lp)
            if st.st_size == rsize and int(st.st_mtime) == rtime:
                kept += 1
                continue
            retire(lp, today)
        except FileNotFoundError:
            pass
        os.makedirs(os.path.dirname(lp), exist_ok=True)
        part = lp + ".part"
        try:
            sf.get(rpath, part)
            os.replace(part, lp)
            os.utime(lp, (rtime, rtime))
            got += 1
            size += rsize
        except Exception as ex:
            failed += 1
            if failed <= 20:
                log("could not copy %s: %s" % (rpath, ex))
            try:
                os.remove(part)
            except OSError:
                pass
    sf.close()
    # whatever is here but gone from the cabinet: move it aside, keep it for a while
    wanted = {os.path.normcase(local_path(p)) for p in remote if local_path(p)}
    gone = 0
    for _, name in ROOTS:
        base = os.path.join(CURRENT, name)
        for dirpath, _, files in os.walk(base):
            for fn in files:
                p = os.path.join(dirpath, fn)
                if os.path.normcase(p) not in wanted:
                    retire(p, today)
                    gone += 1
    pull_system(c, today)
    c.close()
    prune_old()
    log("done: %d copied (%.1f MB), %d unchanged, %d set aside, %d failed"
        % (got, size / 1e6, kept, gone, failed))
    return failed == 0 or got + kept > 0


def main():
    os.makedirs(DEST, exist_ok=True)
    if "--now" not in sys.argv and os.path.exists(STAMP):
        if time.time() - os.path.getmtime(STAMP) < EVERY:
            return
    # one backup at a time: the first one takes a while and the hourly check must not start
    # a second beside it. A lock left by a crashed run counts as gone after four hours.
    lock = os.path.join(DEST, "running.lock")
    if os.path.exists(lock) and time.time() - os.path.getmtime(lock) < 4 * 3600:
        return
    open(lock, "w").close()
    try:
        ok = backup()
    except SystemExit as ex:        # cab.connect says the cabinet is off or away
        log("cabinet not reachable, will try next hour (%s)" % ex)
        return
    except Exception as ex:
        log("backup stopped: %r" % ex)
        return
    finally:
        try:
            os.remove(lock)
        except OSError:
            pass
    if ok:
        with open(STAMP, "w") as f:
            f.write(datetime.datetime.now().isoformat())


if __name__ == "__main__":
    main()
