#!/bin/zsh
set -e
cd "${0:A:h}"
if [[ ! -x "Source Audio.app/Contents/MacOS/SourceAudio" ]]; then
  "${0:A:h}/Construire Source Audio.command"
fi
open "Source Audio.app"
