import sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import cab
cmd = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
t = int(sys.argv[2]) if len(sys.argv) > 2 else 180
c = cab.connect()
print(cab.run(c, cmd, t))
c.close()
