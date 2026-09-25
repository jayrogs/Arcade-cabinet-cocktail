#!/bin/bash
# Sends the cabinet screen to the video server as real video. Only runs while somebody
# is watching: the server starts it and stops it again.
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-0

FPS=20
BITRATE=800k
SCALE=
[ -f /home/jayrogs/stream/quality.conf ] && . /home/jayrogs/stream/quality.conf
FIFOMARK=/tmp/cabvid

# The Pi can only record its screen once at a time, and one forgotten recorder stops
# every later one from starting. Clear anything left behind.
for p in $(pgrep -x wf-recorder); do kill -9 $p 2>/dev/null; done
sleep 0.5

# WHICH SQUEEZER. The Pi's own video chip is far cheaper than the processor, but it can
# jam, and once it has jammed only a restart of the Pi frees it. There is no safe way to
# ask whether it is jammed: a jammed one swallows the question and never answers, and it
# ignores being told to stop, so anything that asks hangs for good. So the chip is used
# only when this file says to:
#
#     touch /home/jayrogs/stream/use_chip      chip, after a restart of the Pi
#     rm    /home/jayrogs/stream/use_chip      back to the processor
if [ -f /home/jayrogs/stream/use_chip ]; then
  CODEC=(-c h264_v4l2m2m -p b=$BITRATE -p g=40)
else
  # the processor's own squeezer, set as light as it goes; a cabinet screen hardly
  # changes, so it costs much less than a moving picture would
  case "$FPS" in
    12) CRF=32 ;;
    15) CRF=31 ;;
    25) CRF=25 ;;
    *)  CRF=28 ;;
  esac
  CODEC=(-c libx264 -p preset=ultrafast -p tune=zerolatency -p crf=$CRF -p g=40)
fi

# The sound rides along with the picture, in the same stream, so the two cannot drift
# apart and there is nothing separate to start. It is what the cabinet itself is
# playing, heard from whichever output it is playing through: the Pi 4's headphone jack,
# a USB sound card or HDMI all work without changing this.
SOUND=@DEFAULT_MONITOR@

# The picture goes into a pipe and is passed straight on, untouched. The SOUND is
# picked up here rather than by the recorder: the recorder's own way of mixing the two
# produced a stream the next program could not make sense of.
# -y so it never stops to ask a question nobody is there to answer. -D so a STILL screen
# still sends pictures: without it a quiet shelf produces nothing and the browser gives
# up. The picture is turned upright on the way, because the monitor is mounted sideways.
FIFO=/tmp/cabvid
# NOTHING is turned or shrunk here any more. Turning the picture upright cost this Pi
# most of a core (82% against 64% at 600 MHz), and a phone can turn it on its own screen
# for nothing. The picture goes out exactly as the screen holds it, lying on its side,
# and the page stands it up.
FILTER=
[ -n "$SCALE" ] && FILTER="scale=$SCALE"
rm -f $FIFO
mkfifo $FIFO

wf-recorder -y -D -x yuv420p -r $FPS ${FILTER:+-F "$FILTER"} "${CODEC[@]}"             -m mpegts -f $FIFO >/tmp/cabvid.log 2>&1 &
WF=$!
ffmpeg -loglevel warning -fflags nobuffer -flags low_delay        -i $FIFO        -f pulse -thread_queue_size 1024 -i "$SOUND"        -map 0:v:0 -map 1:a:0 -c:v copy -c:a libopus -b:a 96k -ac 2        -f rtsp -rtsp_transport tcp rtsp://127.0.0.1:8554/cab        >>/tmp/cabvid.log 2>&1 &
FF=$!
trap 'kill -9 $WF $FF 2>/dev/null; rm -f $FIFO' EXIT INT TERM
# Either half stopping ends the whole feed, so the video server starts a fresh one. Waiting
# on the sound half alone left a feed with no picture running for hours.
wait -n $WF $FF
