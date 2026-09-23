#!/bin/bash
# Builds Flycast's libretro core for OpenGL ES (the Pi 4's mature graphics driver).
exec >> /home/jayrogs/flycast_build.log 2>&1
echo "=== $(date) start"
cd /home/jayrogs
[ -d flycast-src ] || git clone --depth 1 --recursive --shallow-submodules https://github.com/flyinghead/flycast.git flycast-src
cd flycast-src && git log -1 --format='commit %h %cd'
cmake -B build-gles -G Ninja -DCMAKE_BUILD_TYPE=Release -DLIBRETRO=ON -DUSE_GLES=ON -DUSE_VULKAN=OFF
nice -n 15 ninja -C build-gles -j3
echo "=== $(date) done rc=$?"
ls -la build-gles/*.so 2>/dev/null
