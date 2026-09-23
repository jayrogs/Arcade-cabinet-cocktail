import os, sys, time, paramiko
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
PW = os.environ["PIPW"]
c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.1.175", username="jayrogs", password=PW, timeout=20)
def run(cmd, t=90):
    i,o,e = c.exec_command("export XDG_RUNTIME_DIR=/run/user/1000; export WAYLAND_DISPLAY=wayland-0; " + cmd, timeout=t)
    return (o.read()+e.read()).decode(errors="replace").strip()
run("pkill -f '[d]rcocktail.sh'; pkill -f '[d]rcocktail.love'; sleep 3")
s = c.open_sftp(); s.put(r"C:\Users\jayru\Desktop\CabMenu\games\DrCocktail\drcocktail.love", "/home/jayrogs/drcocktail.love"); s.close()
run("setsid nohup /home/jayrogs/drcocktail.sh < /dev/null > /dev/null 2>&1 & disown")
print("waiting for the attract demo so the frame has capsules in it...")
time.sleep(40)
print("running:", run("pgrep -a love") or "NOT RUNNING")
run("grim /tmp/caps.png")
s = c.open_sftp(); s.get("/tmp/caps.png", os.environ["TEMP"] + r"\picab\pi_caps.png"); s.close()
c.close()
