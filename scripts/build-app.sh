#!/usr/bin/env bash
# Compila Lagoon y arma build/Lagoon.app (firmada ad-hoc).
#
#   ./scripts/build-app.sh            → compila en modo release
#   ./scripts/build-app.sh --install  → además copia la app a /Applications
#   ./scripts/build-app.sh --run      → además la abre
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/Lagoon.app"
CONFIG="${CONFIG:-release}"

INSTALL=0
RUN=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --run) RUN=1 ;;
    *) echo "Opción desconocida: $arg" >&2; exit 1 ;;
  esac
done

if ! command -v swift >/dev/null 2>&1; then
  echo "No se encontró 'swift'. Instala Xcode o las Command Line Tools:  xcode-select --install" >&2
  exit 1
fi

echo "▸ Compilando ($CONFIG)…"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "▸ Armando Lagoon.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Lagoon" "$APP/Contents/MacOS/Lagoon"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# "Ahora suena" de cualquier app (Vendor/mediaremote-adapter, BSD-3): un framework que carga
# /usr/bin/perl, más un pequeño cliente para comprobar que sigue funcionando.
echo "▸ Compilando el adaptador de música…"
MRA="$ROOT/Vendor/mediaremote-adapter"
FW="$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
ARCHS=(-arch arm64 -arch x86_64)
mkdir -p "$FW/Versions/A/Resources" "$APP/Contents/Helpers"
clang -dynamiclib -fobjc-arc -fvisibility=default "${ARCHS[@]}" -mmacosx-version-min=14.0 \
  -I"$MRA/include" -I"$MRA/src" \
  "$MRA"/src/adapter/*.m "$MRA"/src/private/MediaRemote.m "$MRA"/src/utility/*.m \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name "@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" \
  -o "$FW/Versions/A/MediaRemoteAdapter"
cat > "$FW/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>MediaRemoteAdapter</string>
	<key>CFBundleIdentifier</key>
	<string>app.lagoon.MediaRemoteAdapter</string>
	<key>CFBundleName</key>
	<string>MediaRemoteAdapter</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>0.1.0</string>
</dict>
</plist>
PLIST
ln -sfn A "$FW/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$FW/Resources"
clang -fobjc-arc "${ARCHS[@]}" -mmacosx-version-min=14.0 \
  "$MRA/src/test/main.m" "$MRA/src/test/NowPlayingTest.m" \
  -framework Foundation -framework MediaPlayer \
  -o "$APP/Contents/Helpers/MediaRemoteAdapterTestClient"
cp "$MRA/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"

echo "▸ Firmando (ad-hoc)…"
codesign --force --sign - --timestamp=none "$FW" >/dev/null
codesign --force --sign - --timestamp=none "$APP/Contents/Helpers/MediaRemoteAdapterTestClient" >/dev/null
codesign --force --sign - --timestamp=none "$APP" >/dev/null

echo "✓ Listo: $APP"

if [[ $INSTALL -eq 1 ]]; then
  echo "▸ Instalando en /Applications…"
  pkill -x Lagoon 2>/dev/null || true
  rm -rf "/Applications/Lagoon.app"
  cp -R "$APP" "/Applications/Lagoon.app"
  APP="/Applications/Lagoon.app"
  echo "✓ Instalada en $APP"
fi

if [[ $RUN -eq 1 ]]; then
  pkill -x Lagoon 2>/dev/null || true
  open "$APP"
fi
