#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="$project_root/build/linux/x64/release/bundle"
if [[ ! -x "$bundle/kirozai" ]]; then
  echo 'Falta el ejecutable Linux. Ejecuta flutter build linux --release.' >&2
  exit 1
fi

package_root="$(mktemp -d)"
trap 'rm -rf "$package_root"' EXIT
install -d "$package_root/DEBIAN" "$package_root/opt/kirozai" \
  "$package_root/usr/bin" "$package_root/usr/share/applications" \
  "$package_root/usr/share/icons/hicolor/scalable/apps" "$project_root/dist"
cp -a "$bundle/." "$package_root/opt/kirozai/"

cat > "$package_root/DEBIAN/control" <<'CONTROL'
Package: kirozai
Version: 0.1.0
Section: graphics
Priority: optional
Architecture: amd64
Maintainer: Kirozai Project
Depends: libc6, libstdc++6, libgtk-3-0 | libgtk-3-0t64, libglib2.0-0 | libglib2.0-0t64
Description: Editor de dibujo Kirozai
 Lienzo con pincel, borrador, formas, capas y exportación PNG.
CONTROL

cat > "$package_root/usr/bin/kirozai" <<'LAUNCHER'
#!/bin/sh
exec /opt/kirozai/kirozai "$@"
LAUNCHER
chmod 755 "$package_root/usr/bin/kirozai"

cat > "$package_root/usr/share/applications/kirozai.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Kirozai
Comment=Editor de dibujo
Exec=kirozai
Icon=kirozai
Terminal=false
Categories=Graphics;2DGraphics;
DESKTOP

install -m 644 "$project_root/packaging/kirozai.svg" \
  "$package_root/usr/share/icons/hicolor/scalable/apps/kirozai.svg"
dpkg-deb --root-owner-group --build "$package_root" \
  "$project_root/dist/kirozai_0.1.0_amd64.deb"
dpkg-deb --info "$project_root/dist/kirozai_0.1.0_amd64.deb"
