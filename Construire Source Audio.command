#!/bin/zsh
set -e

cd "${0:A:h}"
APP="Source Audio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

clang -fobjc-arc -Wall -Wextra \
  -framework Cocoa \
  -framework CoreAudio \
  Native/main.m \
  -o "$APP/Contents/MacOS/SourceAudio"

codesign --force --deep --sign - "$APP"

echo "Source Audio est prêt : $PWD/$APP"
open "$APP"
