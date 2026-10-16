#!/bin/sh
# Builds the adbflashimg binary.
set -e

cd "$(dirname "$0")"

valac --pkg gio-2.0 --pkg gio-unix-2.0 --pkg posix \
      -X -w \
      -o adbflashimg.bin \
      adbflashimg/main.vala \
      adbflashimg/jadb/*.vala

echo "built $(pwd)/adbflashimg.bin"