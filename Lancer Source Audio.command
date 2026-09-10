#!/bin/zsh
set -e
cd "${0:A:h}"
if [[ ! -d "Source Audio.app" ]]; then
  "${0:A:h}/Construire Source Audio.command"
fi
open "Source Audio.app"
