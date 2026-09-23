import os, sys, paramiko, time
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
PW = os.environ["PIPW"]
c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.1.175", username="jayrogs", password=PW, timeout=25)
def run(cmd, t=180):
    i, o, e = c.exec_command("export XDG_RUNTIME_DIR=/run/user/1000; export WAYLAND_DISPLAY=wayland-0; " + cmd, timeout=t)
    return (o.read() + e.read()).decode(errors="replace").strip()

print(run("[ -f /tmp/cab.pid ] && kill $(cat /tmp/cab.pid); pkill -f '[c]abmenu'; sleep 2; echo stopped"))
s = c.open_sftp(); s.put(r"C:\Users\jayru\Desktop\CabMenu\cabmenu.love", "/home/jayrogs/cabmenu.love"); s.close()

shots = sys.argv[1].split(",") if len(sys.argv) > 1 else ["systems", "arcade"]
save = "/home/jayrogs/.local/share/love/cabmenu"
run("rm -f %s/shot_*.png" % save)
for name in shots:
    print(name, run("cd ~; timeout 20 love /home/jayrogs/cabmenu.love --shot=%s >/dev/null 2>&1; echo done" % name))
print(run("ls -1 %s/" % save))
s = c.open_sftp()
out = os.environ["TEMP"] + r"\picab"
for name in shots:
    try:
        s.get("%s/shot_%s.png" % (save, name), "%s\\cab_%s.png" % (out, name))
        print("got", name)
    except Exception as ex:
        print("missing", name, ex)
s.close()
run("setsid nohup /home/jayrogs/cab.sh < /dev/null > /dev/null 2>&1 & disown")
c.close()
