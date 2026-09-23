export XDG_RUNTIME_DIR=/run/user/1000
pkill -f 'love /home/jayrogs/hop.love'
sleep 1
curl -s -m5 "http://127.0.0.1:8080/press?b=10&ms=1200" >/dev/null   # back to the shelf
sleep 7
