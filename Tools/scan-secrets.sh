#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 SasNotch contributors

# Fails when anything that must never be published is tracked or staged:
# private keys, certificates, signing material, API tokens, or absolute paths
# into a personal home folder. Run before every push; CI runs it too.
set -euo pipefail
cd "$(dirname "$0")/.."

failed=0
report() {
    echo "✗ $1" >&2
    failed=1
}

# Files git would publish: everything tracked plus everything staged.
files=("${(@f)$(git ls-files --cached --others --exclude-standard)}")

for file in "${files[@]}"; do
    [[ -f "$file" ]] || continue
    case "$file" in
        *.p12|*.pfx|*.pem|*.cer|*.p8|*.key|*.mobileprovision|*.provisionprofile|*.keychain|*.keychain-db)
            report "signing material is tracked: $file" ;;
        *sparkle_private_key*|*.env|*.env.*)
            report "secret file is tracked: $file" ;;
    esac
done

text_files=("${(@f)$(git grep -Il '' -- . ':!Tools/scan-secrets.sh' 2>/dev/null || true)}")
patterns=(
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    'ghp_[A-Za-z0-9]{36}'
    'github_pat_[A-Za-z0-9_]{40,}'
    'gho_[A-Za-z0-9]{36}'
    'sk-ant-[A-Za-z0-9_-]{20,}'
    'sk-[A-Za-z0-9]{32,}'
    'AKIA[0-9A-Z]{16}'
    'xox[baprs]-[A-Za-z0-9-]{10,}'
    'SPARKLE_ED_PRIVATE_KEY *[:=] *[A-Za-z0-9+/]{40,}'
)
for pattern in "${patterns[@]}"; do
    if (( ${#text_files[@]} )) && [[ -n "${text_files[1]}" ]]; then
        hits="$(grep -nE -- "$pattern" "${text_files[@]}" 2>/dev/null || true)"
        [[ -n "$hits" ]] && report "possible secret ($pattern):"$'\n'"$hits"
    fi
done

# The current account's home folder and login name leak a real username and
# machine layout. Tests use made-up homes such as /Users/test, which stay.
if (( ${#text_files[@]} )) && [[ -n "${text_files[1]}" ]]; then
    me="$(id -un)"
    if [[ "$me" != "runner" ]]; then
        home_hits="$(grep -nF -e "$HOME" -e "/Users/$me" "${text_files[@]}" 2>/dev/null || true)"
        [[ -n "$home_hits" ]] && report "personal paths found:"$'\n'"$home_hits"
    fi
fi

if (( failed == 0 )); then
    echo "✓ No secrets, signing material or personal paths found."
fi
exit $failed
