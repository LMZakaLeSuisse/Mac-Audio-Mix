#!/bin/zsh
set -e

cd "${0:A:h}"
APP="Source Audio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "Build/Info.plist" "$APP/Contents/Info.plist"
cp "Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

clang -fobjc-arc -Wall -Wextra \
  -framework Cocoa \
  -framework CoreAudio \
  Native/main.m \
  -o "$APP/Contents/MacOS/SourceAudio"

codesign --force --deep --sign - "$APP"

# Archive prête à télécharger : elle conserve l’exécutable et ses permissions.
rm -f "TELECHARGER-Source-Audio-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "TELECHARGER-Source-Audio-macOS.zip"

echo "Source Audio est prêt : $PWD/$APP"
echo "Archive de distribution : $PWD/TELECHARGER-Source-Audio-macOS.zip"
open "$APP"
