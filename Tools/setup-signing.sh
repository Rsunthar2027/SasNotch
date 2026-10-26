#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
# Modified for SasNotch by SasNotch contributors, 2026

# Creates a stable, self-signed code-signing identity named "SasNotch Utils
# Signing" in a dedicated keychain. build.sh uses it automatically, giving every
# build the same code signature — so macOS keeps granted permissions
# (Accessibility, Screen Recording) across updates instead of re-prompting.
#
# This identity name keeps its original "SasNotch Self-Signed" on purpose: it
# is the lookup key build.sh matches, and the released app's designated
# requirement is pinned to this exact certificate. Renaming it would change that
# requirement and drop every user's granted permissions. The name lives only in
# the keychain and codesign output, never in anything the app shows.
#
# Free, offline, and idempotent (re-running is a no-op once a working identity exists).
# It does NOT replace Apple notarization: downloaded builds still show Gatekeeper's
# "unverified developer" prompt on first launch. It only stabilizes the identity.
#
# Maintainers: official releases use the protected release-signing environment.
# Run this only to get the same permission-preserving behavior for local builds.
set -euo pipefail

IDENTITY="SasNotch Self-Signed"
KC="$HOME/Library/Keychains/sasnotch-signing.keychain-db"
KCPASS="sasnotch-signing"

# A find-identity listing also names certificates codesign then rejects, and -v
# excludes every self-signed one; ask codesign itself with a throwaway copy.
identity_can_sign() {
    local probe signed=1
    # Locked after every reboot; a locked keychain cannot sign, and a false
    # answer here would delete it and reissue the identity.
    security unlock-keychain -p "$KCPASS" "$KC" 2>/dev/null || true
    probe="$(mktemp)"
    cp /bin/echo "$probe"
    codesign --force --strip-disallowed-xattrs --sign "$IDENTITY" "$probe" >/dev/null 2>&1 && signed=0
    rm -f "$probe"
    return $signed
}

if identity_can_sign; then
    echo "✓ Signing identity already installed."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 3650 -nodes \
    -subj "/CN=$IDENTITY/O=SasNotch" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null
# The PBE and MAC algorithms are named explicitly: the stock /usr/bin/openssl
# is LibreSSL, which rejects OpenSSL 3's -legacy flag, while OpenSSL 3's
# defaults (AES-256, PBKDF2) are newer than what security(1) imports reliably.
# These three are accepted by both and produce the same portable file.
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/id.p12" -passout pass:"$KCPASS" -name "$IDENTITY" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 || {
    echo "✗ openssl pkcs12 could not export the identity." >&2
    exit 1
}

security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KCPASS" "$KC"
security set-keychain-settings "$KC"            # no auto-lock
security unlock-keychain -p "$KCPASS" "$KC"
security import "$WORK/id.p12" -k "$KC" -P "$KCPASS" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KC" >/dev/null 2>&1
EXISTING=$(security list-keychains -d user | sed 's/"//g' | xargs)
security list-keychains -d user -s "$KC" ${=EXISTING}

# Import succeeding is not evidence codesign can sign with it: read it back the
# same way build.sh looks it up, so a broken search list fails here and not as
# a silent ad-hoc fallback three builds later.
identity_can_sign || {
    echo "✗ Identity imported but codesign cannot sign with it; keychain search list may be off." >&2
    exit 1
}
echo "✓ Created signing identity '$IDENTITY'. Future ./build.sh runs use it automatically."
