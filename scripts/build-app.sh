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

echo "▸ Firmando (ad-hoc)…"
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
