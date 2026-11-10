# Encrypt backup.sh (age) and the .env files (sops: hop/.env, hop/snippets.json5, sketchybar/env.local.sh) into their .enc copies.
encrypt:
    [ ! -f backup.sh ] || age -r age16td0lf6gaycxwef5ga3yhkjxrrcmptrcu25g4s9zg5wcm0qzf4uqdj94pf -o backup.sh.enc backup.sh
    bash scripts/env.sh encrypt

# Decrypt backup.sh and the .env files from their .enc copies (needs the age key).
decrypt:
    age --decrypt -i "$HOME/Library/Application Support/sops/age/keys.txt" -o backup.sh backup.sh.enc
    bash scripts/env.sh decrypt

# Edit an encrypted .env in place (e.g. just edit-env hop/.env), then refresh the decrypted copy.
edit-env path:
    SOPS_AGE_KEY_FILE="$HOME/Library/Application Support/sops/age/keys.txt" sops edit --input-type dotenv --output-type dotenv {{path}}.enc
    bash scripts/env.sh decrypt

# This Mac's Brewfile: hosts/<host>/Brewfile (host = bootstrap's choice, else the hostname).
brewfile := "hosts/" + `cat ~/.config/dotfiles/host 2>/dev/null || scutil --get LocalHostName | tr '[:upper:]' '[:lower:]'` + "/Brewfile"

# Formulae from untrusted taps are skipped by the dump — check `just brew-untrusted` first.
# Snapshot everything installed (formulae, casks, taps, mas, go, vscode) into this Mac's Brewfile.
brew-dump:
    brew bundle dump --file {{brewfile}} --force

# What this Mac's Brewfile lists but is not installed on this machine.
brew-check:
    brew bundle check --file {{brewfile}} --verbose

# What is installed but missing from this Mac's Brewfile (dry run; add --force to uninstall it).
brew-extra:
    brew bundle cleanup --file {{brewfile}}

# Taps Homebrew currently ignores because they are not trusted.
brew-untrusted:
    brew tap-info --installed --json | jq -r '.[] | select(.trusted == false) | .name'

# Pack GPG keys, ~/.ssh and the age key into one passphrase-encrypted file (the .env files come from the repo).
secrets-export out_dir="~/Downloads":
    bash scripts/secrets.sh export {{out_dir}}

# Unpack a secrets bundle from `just secrets-export` into place on this machine.
secrets-import file:
    bash scripts/secrets.sh import {{file}}
