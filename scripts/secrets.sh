#!/bin/bash
# ============================================================================
#  secrets.sh — move the machine secrets that never go into the public dotfiles
# ============================================================================
#
#  export [out-dir]   pack everything below into ONE passphrase-encrypted file
#                     (age -p) — default out-dir: ~/Downloads
#  import <file>      unpack it on a new machine into the right places,
#                     backing up anything that would be overwritten
#
#  What travels:
#    gpg      all secret + public keys and ownertrust
#    ssh      ~/.ssh (keys, config, known_hosts)
#    age      ~/Library/Application Support/sops/age/keys.txt, ~/age.agekey
#    certs    every identity (certificate + private key) in the login keychain:
#             personal e-ID certificates, Apple Development, Developer ID
#             (macOS asks once per private key: enter the login password, Always Allow)
#
#  The .env files (hop, sketchybar) are in the repo as sops-encrypted *.enc;
#  import decrypts them with the age key it just placed (scripts/env.sh).
#
#  Testing only: AGE_RECIPIENT=age1… (export) / AGE_IDENTITY=file (import)
#  replace the passphrase prompt.
# ============================================================================

set -uo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
AGE_KEYS="$HOME/Library/Application Support/sops/age/keys.txt"

if [[ -t 1 ]]; then
    G=$'\033[38;5;78m'; Y=$'\033[38;5;214m'; R=$'\033[38;5;203m'; D=$'\033[38;5;245m'; B=$'\033[1m'; N=$'\033[0m'
else
    G=""; Y=""; R=""; D=""; B=""; N=""
fi
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
skip() { printf '  %s–%s %s\n' "$D" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '  %s✗ %s%s\n' "$R" "$*" "$N"; exit 1; }

command -v age >/dev/null || die "age is not installed (brew install age)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/secrets.XXXXXX")" || die "mktemp failed"
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

stash() { # stash <src> <name-in-bundle>
    local src="$1" dst="$WORK/bundle/$2"
    if [[ -e "$src" ]]; then
        mkdir -p "$(dirname "$dst")"
        # sockets (sshd's ~/.ssh/agent) cannot be copied and are dropped below — keep cp quiet about them
        cp -Rp "$src" "$dst" 2> >(grep -v 'is a socket' >&2) && ok "$2"
    else
        skip "$2 ${D}(not on this machine)${N}"
    fi
}

cmd_export() {
    local out_dir="${1:-$HOME/Downloads}" host out
    host="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
    out="$out_dir/secrets-$host-$(date +%Y%m%d).tar.gz.age"
    mkdir -p "$WORK/bundle" "$out_dir" || die "cannot create $out_dir"
    printf '\n  %sExporting secrets from %s%s\n\n' "$B" "$host" "$N"

    # gpg
    if command -v gpg >/dev/null && gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec'; then
        mkdir -p "$WORK/bundle/gpg"
        printf '  %s  gpg may ask for each key passphrase%s\n' "$D" "$N"
        gpg --armor --export-secret-keys >"$WORK/bundle/gpg/secret.asc" || die "gpg secret key export failed"
        gpg --armor --export >"$WORK/bundle/gpg/public.asc"
        gpg --export-ownertrust >"$WORK/bundle/gpg/ownertrust.txt"
        ok "gpg ($(gpg --list-secret-keys --with-colons | grep -c '^sec') secret keys)"
    else
        skip "gpg (no secret keys)"
    fi

    # certificates with private keys (.p12): iCloud Keychain does not carry them
    local login_kc="$HOME/Library/Keychains/login.keychain-db" pass n
    n=$(security find-identity 2>/dev/null | sed -n 's/^ *\([0-9]*\) identities found$/\1/p' | head -n 1)
    if [[ "${n:-0}" -gt 0 ]]; then
        mkdir -p "$WORK/bundle/certs"
        pass=$(openssl rand -hex 24)
        printf '  %s  macOS asks for each private key: login password, then Always Allow%s\n' "$D" "$N"
        if security export -k "$login_kc" -t identities -f pkcs12 -P "$pass" -o "$WORK/bundle/certs/identities.p12" >/dev/null 2>&1; then
            printf '%s' "$pass" >"$WORK/bundle/certs/password"
            ok "certs ($n identities from the login keychain)"
        else
            rm -rf "$WORK/bundle/certs"
            warn "certs: the keychain export was refused — export them by hand in Keychain Access (My Certificates › Export…)"
        fi
    else
        skip "certs (no identities in the login keychain)"
    fi

    stash "$HOME/.ssh" "ssh"
    stash "$AGE_KEYS" "age/keys.txt"
    stash "$HOME/age.agekey" "age/age.agekey"

    # never carry sockets or agent junk
    find "$WORK/bundle" \( -type s -o -name '*.sock' \) -delete 2>/dev/null
    rm -rf "$WORK/bundle/ssh/agent"
    find "$WORK/bundle" -mindepth 1 -type d -empty -delete 2>/dev/null
    (cd "$WORK/bundle" && find . -type f | sort) >"$WORK/bundle/MANIFEST"

    printf '\n  %s  choose a passphrase — you need it on the new machine%s\n' "$D" "$N"
    if [[ -n "${AGE_RECIPIENT:-}" ]]; then
        tar -C "$WORK/bundle" -czf - . | age -r "$AGE_RECIPIENT" -o "$out" || die "encryption failed"
    else
        tar -C "$WORK/bundle" -czf - . | age -p -o "$out" || die "encryption failed"
    fi
    chmod 600 "$out"
    printf '\n  %s✓ %s%s  %s(%s)%s\n' "$G$B" "$out" "$N" "$D" "$(du -h "$out" | cut -f1 | tr -d ' ')" "$N"
    printf '  %s  copy it to the new machine (USB / AirDrop), run: just secrets-import <file>, then delete it%s\n\n' "$D" "$N"
}

place() { # place <name-in-bundle> <dest> <mode>
    local src="$WORK/bundle/$1" dst="$2" mode="$3"
    [[ -e "$src" ]] || { skip "$1 ${D}(not in the bundle)${N}"; return 0; }
    mkdir -p "$(dirname "$dst")"
    if [[ -e "$dst" ]] && ! diff -rq "$src" "$dst" >/dev/null 2>&1; then
        mv "$dst" "$dst.bak-$(date +%Y%m%d-%H%M%S)" && warn "existing ${dst/#$HOME/~} kept as .bak-*"
    fi
    rm -rf "$dst"
    cp -Rp "$src" "$dst"
    chmod "$mode" "$dst"
    ok "$1 ${D}→ ${dst/#$HOME/~}${N}"
}

cmd_import() {
    local file="${1:-}"
    [[ -f "$file" ]] || die "usage: secrets.sh import <secrets-….tar.gz.age>"
    printf '\n  %sImporting secrets from %s%s\n\n' "$B" "$(basename "$file")" "$N"
    mkdir -p "$WORK/bundle"
    if [[ -n "${AGE_IDENTITY:-}" ]]; then
        age -d -i "$AGE_IDENTITY" "$file" | tar -C "$WORK/bundle" -xzf - || die "decryption failed"
    else
        age -d "$file" | tar -C "$WORK/bundle" -xzf - || die "decryption failed (wrong passphrase?)"
    fi

    # ssh: directory 700, private keys 600, the rest 644
    if [[ -d "$WORK/bundle/ssh" ]]; then
        place "ssh" "$HOME/.ssh" 700
        find "$HOME/.ssh" -type f -exec chmod 600 {} \;
        find "$HOME/.ssh" -type f \( -name '*.pub' -o -name 'known_hosts*' \) -exec chmod 644 {} \;
    fi
    place "age/keys.txt" "$AGE_KEYS" 600
    place "age/age.agekey" "$HOME/age.agekey" 600
    # bundles from before the .env files moved into the repo: keep only what is not there yet
    [[ -f "$DOTFILES/sketchybar/env.local.sh.enc" ]] || place "dotfiles/sketchybar/env.local.sh" "$DOTFILES/sketchybar/env.local.sh" 600

    if [[ -f "$WORK/bundle/gpg/secret.asc" ]]; then
        command -v gpg >/dev/null || die "gpg is not installed — run the bootstrap's Homebrew step first"
        mkdir -p "$HOME/.gnupg" && chmod 700 "$HOME/.gnupg"
        gpg --batch --import "$WORK/bundle/gpg/public.asc" 2>/dev/null
        gpg --batch --import "$WORK/bundle/gpg/secret.asc" 2>/dev/null || warn "gpg secret key import reported problems"
        gpg --import-ownertrust "$WORK/bundle/gpg/ownertrust.txt" 2>/dev/null
        ok "gpg ($(gpg --list-secret-keys --with-colons 2>/dev/null | grep -c '^sec') secret keys in the keyring)"
    else
        skip "gpg (not in the bundle)"
    fi
    if [[ -f "$WORK/bundle/certs/identities.p12" ]]; then
        # -A: apps may use the keys without asking (codesign, browsers, proXSign)
        if security import "$WORK/bundle/certs/identities.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
            -f pkcs12 -P "$(cat "$WORK/bundle/certs/password")" -A >/dev/null 2>&1; then
            ok "certs → login keychain ($(security find-identity 2>/dev/null | sed -n 's/^ *\([0-9]*\) identities found$/\1/p' | head -n 1) identities)"
        else
            mkdir -p "$HOME/Desktop/certs-import" && chmod 700 "$HOME/Desktop/certs-import"
            cp "$WORK/bundle/certs/identities.p12" "$WORK/bundle/certs/password" "$HOME/Desktop/certs-import/"
            warn "certs did not import — open ~/Desktop/certs-import/identities.p12 (password in the file next to it), then delete the folder"
        fi
    else
        skip "certs (not in the bundle)"
    fi

    if [[ -f "$AGE_KEYS" ]] && command -v sops >/dev/null; then
        bash "$DOTFILES/scripts/env.sh" decrypt || warn "the .env files did not decrypt — run: just decrypt"
    else
        warn "sops or the age key missing — decrypt the .env files later: just decrypt"
    fi
    printf '\n  %s✓ done%s %s— delete %s now%s\n\n' "$G$B" "$N" "$D" "$file" "$N"
}

case "${1:-}" in
    export) shift; cmd_export "$@" ;;
    import) shift; cmd_import "$@" ;;
    *) sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
