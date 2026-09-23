export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=-all XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
pkill -f Game.exe; pkill -f wineserver; sleep 3
/usr/local/bin/box86 /opt/wine/wine-9.0-x86/bin/wine reg add "HKCU\Software\Wine\DllOverrides" /v mscoree /d "" /f
/usr/local/bin/box86 /opt/wine/wine-9.0-x86/bin/wine reg add "HKCU\Software\Wine\DllOverrides" /v mshtml /d "" /f
sleep 2
grep -a -c mscoree $WINEPREFIX/user.reg
pkill -f wineserver
echo done
