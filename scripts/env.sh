#!/bin/bash
# ============================================================================
#  env.sh — the dotfiles' secret .env files, committed only as sops-encrypted *.enc
# ============================================================================
#
#  decrypt   write each <file> from <file>.enc (needs the age key and sops)
#  encrypt   write <file>.enc from each <file> whose content changed
#  status    which files are present, decrypted or missing
#
#  Files: hop/.env (${NAME} values in hop/config.json5),
#         hop/snippets.json5 (hop snippets: addresses, IDs; the repo is public),
#         tip/.env (${NAME} values in tip/config.json5: the markets plugin's etherscan key)
# ============================================================================

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

FILES=(hop/.env hop/snippets.json5 tip/.env)
AGE_KEYS="$HOME/Library/Application Support/sops/age/keys.txt"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$AGE_KEYS}"
# .env files stay dotenv (one value per key in the .enc); anything else is one opaque blob.
fmt_for() {
    case "$1" in
        *.env|*.sh) fmt=(--input-type dotenv --output-type dotenv) ;;
        *) fmt=(--input-type binary --output-type binary) ;;
    esac
}

need() {
    command -v sops >/dev/null || { echo "sops is not installed (brew install sops)" >&2; exit 1; }
    [[ -f "$SOPS_AGE_KEY_FILE" ]] || { echo "no age key at $SOPS_AGE_KEY_FILE (just secrets-import <file>)" >&2; exit 1; }
}

cmd_decrypt() {
    need
    local f rc=0 tmp
    for f in "${FILES[@]}"; do
        [[ -f "$f.enc" ]] || { echo "  – $f (no $f.enc)"; continue; }
        fmt_for "$f"
        tmp="$(mktemp)"
        if sops -d "${fmt[@]}" "$f.enc" >"$tmp" 2>/dev/null; then
            mv "$tmp" "$f" && chmod 600 "$f" && echo "  ✓ $f"
        else
            rm -f "$tmp"; echo "  ✗ $f (decryption failed)" >&2; rc=1
        fi
    done
    return $rc
}

cmd_encrypt() {
    need
    local f
    for f in "${FILES[@]}"; do
        [[ -f "$f" ]] || { echo "  – $f (not here)"; continue; }
        fmt_for "$f"
        if [[ -f "$f.enc" ]] && sops -d "${fmt[@]}" "$f.enc" 2>/dev/null | cmp -s - "$f"; then
            echo "  = $f.enc (unchanged)"
            continue
        fi
        sops -e "${fmt[@]}" --filename-override "$f" "$f" >"$f.enc.tmp" && mv "$f.enc.tmp" "$f.enc" && echo "  ✓ $f.enc" \
            || { rm -f "$f.enc.tmp"; echo "  ✗ $f.enc" >&2; return 1; }
    done
}

cmd_status() {
    local f
    for f in "${FILES[@]}"; do
        printf '  %-26s %s, %s\n' "$f" "$([[ -f "$f" ]] && echo decrypted || echo 'not decrypted')" "$([[ -f "$f.enc" ]] && echo 'has .enc' || echo 'no .enc')"
    done
}

case "${1:-}" in
    decrypt) cmd_decrypt ;;
    encrypt) cmd_encrypt ;;
    status)  cmd_status ;;
    *) sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
