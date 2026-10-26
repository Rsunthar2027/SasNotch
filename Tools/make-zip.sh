#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 SasNotch contributors

# Packages the built app as dist/SasNotch.zip: the archive the one-line
# installer unzips into /Applications and the one Sparkle updates from.
# Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/stage/SasNotch.app"
if [[ ! -d "$APP" ]]; then
    echo "✗ $APP not found — run ./build.sh first" >&2
    exit 1
fi
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p dist
rm -f dist/SasNotch.zip
# ditto keeps the bundle's symlinks, permissions and signature intact. No
# --sequesterRsrc: that adds a __MACOSX folder the installer would unzip
# into Applications.
ditto -c -k --keepParent "$APP" dist/SasNotch.zip
echo "✓ ZIP ready: dist/SasNotch.zip"
