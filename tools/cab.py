"""Reaching the cabinet, from the same house or from anywhere.

Tries the home address first, then the Tailscale one, so the same scripts work whether
this machine is on Jay's network or somewhere else entirely.
"""
import os, socket, paramiko

# the home addresses first, then the cabinet by its own name on the home network (the
# Wi-Fi address can change after a restart), then Tailscale
HOSTS = ["192.168.1.145", "192.168.1.175", "picade.local", "100.73.167.50", "arcade-cab"]
USER = "jayrogs"

def reachable(host, port=22, timeout=4):
    s = socket.socket()
    s.settimeout(timeout)
    try:
        s.connect((host, port))
        return True
    except Exception:
        return False
    finally:
        s.close()

def connect(timeout=20):
    pw = os.environ.get("PIPW")
    last = None
    for host in HOSTS:
        if not reachable(host):
            continue
        c = paramiko.SSHClient()
        c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        try:
            c.connect(host, username=USER, password=pw, timeout=timeout)
            c.cab_host = host
            return c
        except Exception as ex:
            last = ex
    raise SystemExit("cannot reach the cabinet on any of %s (%s)" % (", ".join(HOSTS), last))

def run(c, cmd, t=180):
    pre = ("export XDG_RUNTIME_DIR=/run/user/1000; export WAYLAND_DISPLAY=wayland-0; "
           "export DEBIAN_FRONTEND=noninteractive; ")
    i, o, e = c.exec_command(pre + cmd, timeout=t)
    return (o.read() + e.read()).decode(errors="replace").strip()
