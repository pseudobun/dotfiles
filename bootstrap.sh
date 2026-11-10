#!/bin/bash
# ============================================================================
#  pseudobun/dotfiles — bootstrap
# ============================================================================
#
#  Rebuilds a Mac from scratch: CLI tools, Homebrew + Brewfile, shell, keys,
#  dotfile links, sketchybar, dev tools, macOS defaults and services.
#
#  Fresh machine:
#    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/pseudobun/dotfiles/main/bootstrap.sh)"
#
#  Unattended (every prompt takes its default):
#    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/pseudobun/dotfiles/main/bootstrap.sh)" -- --yes
#
#  Options:
#    -y, --yes          answer every prompt with its default, never wait for input
#    --only a,b         run only these steps (ids from --list)
#    --skip a,b         skip these steps
#    --no-mas           skip Mac App Store apps (no App Store login, e.g. in a VM)
#    --role laptop|server
#                       laptop: paw, sketchybar, hidden menu bar
#                       server: headless box: hop only, never sleeps
#                       default: the last choice, else laptop when there is a battery
#    --list             list steps and exit
#    -h, --help         this help
#
#  Log: ~/Library/Logs/dotfiles-bootstrap.log
#
#  Written for the macOS system bash (3.2): no associative arrays, no mapfile.
# ============================================================================

set -uo pipefail

# --- state -------------------------------------------------------------------
dotfiles_path="$HOME/.dotfiles"
DOTFILES_REPO="https://github.com/pseudobun/dotfiles.git"
SKETCHYBAR_APP_FONT_VERSION="v3.0.20"
DEFAULT_GPG_KEY="3C6FB610DBED15600E8FAEB4389F01C7E97E0262"

ASSUME_YES=0
NO_MAS=0
ONLY=""
SKIP=""
ROLE=""
ROLE_FILE="$HOME/.config/dotfiles/role"
LOG="$HOME/Library/Logs/dotfiles-bootstrap.log"
START_TS=$(date +%s)
STEP_STARTED=$START_TS

STEP_IDS=(xcode clone homebrew secrets shell gpg ssh links fish devtools spicetify macos terminal fonts iterm github apps services)
STEP_TITLES=(
    "Xcode Command Line Tools"
    "Dotfiles repository"
    "Homebrew & Brewfile"
    "Secrets from the old Mac"
    "Fish shell"
    "GPG"
    "SSH key"
    "Dotfile links & sketchybar"
    "Fish configuration"
    "Development tools"
    "Spicetify"
    "macOS defaults"
    "Extra terminals"
    "Bundled fonts"
    "iTerm2 profile"
    "GitHub CLI login"
    "hop & paw"
    "Services"
)
STEP_STATUS=()   # done | skipped | warn | failed
STEP_TIME=()
FOLLOWUPS=()     # manual things to do afterwards
CURRENT=0
CURRENT_WARN=0
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# --- terminal & colours ---------------------------------------------------------
if [[ -t 1 ]]; then IS_TTY=1; else IS_TTY=0; fi
if [[ $IS_TTY -eq 1 && -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_GOLD=$'\033[38;5;222m'; C_WAVE=$'\033[38;5;111m'; C_GREEN=$'\033[38;5;78m'
    C_RED=$'\033[38;5;203m'; C_AMBER=$'\033[38;5;214m'; C_GREY=$'\033[38;5;245m'
    C_VIOLET=$'\033[38;5;141m'
else
    C_RESET=""; C_BOLD=""; C_DIM=""; C_GOLD=""; C_WAVE=""; C_GREEN=""
    C_RED=""; C_AMBER=""; C_GREY=""; C_VIOLET=""
fi
BAR="${C_GREY}│${C_RESET}"

# --- output helpers ---------------------------------------------------------------
strip_ansi() { sed -e $'s/\033\\[[0-9;]*[a-zA-Z]//g'; }
log_raw()  { printf '%s\n' "$*" | strip_ansi >>"$LOG"; }
line()     { printf '  %s  %s\n' "$BAR" "$*"; log_raw "  $*"; }
info()     { line "${C_WAVE}›${C_RESET} $*"; }
success()  { line "${C_GREEN}✓${C_RESET} $*"; }
warn()     { line "${C_AMBER}!${C_RESET} $*"; CURRENT_WARN=1; }
err()      { line "${C_RED}✗${C_RESET} $*"; CURRENT_WARN=1; }
note()     { line "${C_DIM}$*${C_RESET}"; }
followup() { FOLLOWUPS+=("$*"); }

fatal() {
    printf '\n  %s✗ %s%s\n  %sAborting. Log: %s%s\n\n' "$C_RED$C_BOLD" "$1" "$C_RESET" "$C_GREY" "$LOG" "$C_RESET"
    log_raw "FATAL: $1"
    exit 1
}

fmt_duration() {
    local s=$1
    if (( s >= 3600 )); then printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
    elif (( s >= 60 )); then printf '%dm%02ds' $((s / 60)) $((s % 60))
    else printf '%ds' "$s"; fi
}

banner() {
    printf '\n'
    printf '  %s╭──────────────────────────────────────────────────────╮%s\n' "$C_GREY" "$C_RESET"
    printf '  %s│%s  %s◆ pseudobun/dotfiles%s  %sbootstrap%s                      %s│%s\n' "$C_GREY" "$C_RESET" "$C_GOLD$C_BOLD" "$C_RESET" "$C_GREY" "$C_RESET" "$C_GREY" "$C_RESET"
    printf '  %s│%s  %srebuild this Mac from the Brewfile and dotfiles%s      %s│%s\n' "$C_GREY" "$C_RESET" "$C_DIM" "$C_RESET" "$C_GREY" "$C_RESET"
    printf '  %s╰──────────────────────────────────────────────────────╯%s\n' "$C_GREY" "$C_RESET"
    printf '\n'
    printf '  %shost%s %s   %smacOS%s %s   %suser%s %s\n' \
        "$C_GREY" "$C_RESET" "$(scutil --get LocalHostName 2>/dev/null || hostname -s)" \
        "$C_GREY" "$C_RESET" "$(sw_vers -productVersion 2>/dev/null || uname -r)" \
        "$C_GREY" "$C_RESET" "$USER"
    printf '  %srole%s %s   %smode%s %s   %slog%s %s\n' \
        "$C_GREY" "$C_RESET" "$ROLE" \
        "$C_GREY" "$C_RESET" "$([[ $ASSUME_YES -eq 1 ]] && echo unattended || echo interactive)" \
        "$C_GREY" "$C_RESET" "${LOG/#$HOME/~}"
}

step_begin() {
    CURRENT_WARN=0
    STEP_STARTED=$(date +%s)
    printf '\n  %s╭─%s %s%02d/%02d%s  %s%s%s\n' "$C_GREY" "$C_RESET" "$C_GOLD" "$((CURRENT + 1))" "${#STEP_IDS[@]}" "$C_RESET" \
        "$C_BOLD" "${STEP_TITLES[$CURRENT]}" "$C_RESET"
    log_raw ""
    log_raw "=== $((CURRENT + 1))/${#STEP_IDS[@]} ${STEP_TITLES[$CURRENT]} ($(date '+%F %T'))"
}

# status: done | skipped | failed  (done becomes "warn" if the step warned)
step_end() {
    local status="$1" took icon colour label
    if [[ "$status" == "done" && $CURRENT_WARN -eq 1 ]]; then status="warn"; fi
    took=$(( $(date +%s) - STEP_STARTED ))
    STEP_STATUS[$CURRENT]="$status"
    STEP_TIME[$CURRENT]="$took"
    case "$status" in
        done)    icon="✓"; colour="$C_GREEN"; label="done" ;;
        warn)    icon="!"; colour="$C_AMBER"; label="done with warnings" ;;
        skipped) icon="–"; colour="$C_GREY";  label="skipped" ;;
        *)       icon="✗"; colour="$C_RED";   label="failed" ;;
    esac
    printf '  %s╰─%s %s%s %s%s %s%s%s\n' "$C_GREY" "$C_RESET" "$colour" "$icon" "$label" "$C_RESET" "$C_GREY" "$(fmt_duration "$took")" "$C_RESET"
    log_raw "=== $status in $(fmt_duration "$took")"
}

# ask_yes_no "Question?" [y|n]  -> 0 yes, 1 no. Unattended: the default.
ask_yes_no() {
    local question="$1" default="${2:-y}" hint answer
    if [[ "$default" == "y" ]]; then hint="Y/n"; else hint="y/N"; fi
    if [[ $ASSUME_YES -eq 1 ]]; then
        line "${C_VIOLET}?${C_RESET} $question ${C_GREY}› $([[ $default == y ]] && echo yes || echo no) (default)${C_RESET}"
        [[ "$default" == "y" ]]
        return
    fi
    while true; do
        printf '  %s  %s?%s %s %s[%s]%s ' "$BAR" "$C_VIOLET" "$C_RESET" "$question" "$C_GREY" "$hint" "$C_RESET"
        read -r answer </dev/tty
        answer="${answer:-$default}"
        case "$answer" in
            [Yy]|[Yy][Ee][Ss]) log_raw "  ? $question -> yes"; return 0 ;;
            [Nn]|[Nn][Oo])     log_raw "  ? $question -> no";  return 1 ;;
            *) note "please answer y or n" ;;
        esac
    done
}

# ask_input "Prompt" "default"  -> prints the answer on stdout
ask_input() {
    local question="$1" default="$2" answer
    if [[ $ASSUME_YES -eq 1 ]]; then
        line "${C_VIOLET}?${C_RESET} $question ${C_GREY}› ${default:-<empty>} (default)${C_RESET}" >&2
        printf '%s\n' "$default"
        return
    fi
    printf '  %s  %s?%s %s %s(%s)%s ' "$BAR" "$C_VIOLET" "$C_RESET" "$question" "$C_GREY" "$default" "$C_RESET" >&2
    read -r answer </dev/tty
    printf '%s\n' "${answer:-$default}"
}

# Wait for a manual step. 0 = done, 1 = skipped. Unattended: always skipped.
wait_for_manual_step() {
    local answer
    if [[ $ASSUME_YES -eq 1 ]]; then
        note "manual step — skipped in unattended mode"
        return 1
    fi
    printf '  %s  %s↵%s press Enter when done, or %ss%s to skip ' "$BAR" "$C_AMBER" "$C_RESET" "$C_BOLD" "$C_RESET"
    read -r answer </dev/tty
    if [[ "$answer" == "s" || "$answer" == "S" ]]; then note "skipped"; return 1; fi
    return 0
}

# run "label" cmd args...  — runs quietly into the log with a spinner that shows
# the latest log line; prints ✓/✗ with the duration and the log tail on failure.
run() {
    local label="$1"; shift
    local started pid rc i=0 last now cols width
    started=$(date +%s)
    log_raw "  \$ $*"
    if [[ $IS_TTY -eq 1 ]]; then
        "$@" >>"$LOG" 2>&1 </dev/null &
        pid=$!
        cols=$(tput cols 2>/dev/null || echo 100)
        width=$(( cols - ${#label} - 24 )); (( width < 10 )) && width=10
        while kill -0 "$pid" 2>/dev/null; do
            now=$(( $(date +%s) - started ))
            last=$(tail -n 1 "$LOG" 2>/dev/null | tr -d '\r' | strip_ansi | sed 's/^[[:space:]]*//')
            last="${last:0:$width}"
            printf '\r\033[K  %s  %s%s%s %s %s%s · %s%s' "$BAR" "$C_WAVE" "${SPIN[$((i % 10))]}" "$C_RESET" "$label" \
                "$C_GREY" "$(fmt_duration "$now")" "$last" "$C_RESET"
            i=$((i + 1))
            sleep 0.1
        done
        wait "$pid"; rc=$?
        printf '\r\033[K'
    else
        line "${C_WAVE}…${C_RESET} $label"
        "$@" >>"$LOG" 2>&1 </dev/null
        rc=$?
    fi
    now=$(( $(date +%s) - started ))
    if [[ $rc -eq 0 ]]; then
        line "${C_GREEN}✓${C_RESET} $label ${C_GREY}$(fmt_duration "$now")${C_RESET}"
    else
        line "${C_RED}✗${C_RESET} $label ${C_GREY}(exit $rc, $(fmt_duration "$now"))${C_RESET}"
        tail -n 12 "$LOG" | strip_ansi | while IFS= read -r l; do note "    $l"; done
        CURRENT_WARN=1
    fi
    return $rc
}

contains() { case ",$1," in *",$2,"*) return 0 ;; esac; return 1; }

load_brew() {
    if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"; fi
}

# Ask for sudo once and keep it alive for the whole run.
sudo_keepalive() {
    if ! sudo -n true 2>/dev/null; then
        if [[ -r /dev/tty ]] && { : </dev/tty; } 2>/dev/null; then
            line "${C_VIOLET}?${C_RESET} administrator password (asked once, kept for the whole run)"
            sudo -v </dev/tty || fatal "sudo is required."
        else
            fatal "sudo needs a password but there is no terminal. Run with a TTY (ssh -t) or configure passwordless sudo."
        fi
    fi
    ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}

# ============================================================================
# Steps — return 0 done, 2 skipped, anything else failed
# ============================================================================

step_xcode() {
    if xcode-select -p &>/dev/null; then
        success "already installed at $(xcode-select -p)"
        return 0
    fi
    ask_yes_no "Install the Command Line Tools? (required)" || fatal "The Command Line Tools are required."

    # Headless install through softwareupdate — no GUI dialog, works over SSH.
    local marker=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress label
    touch "$marker"
    label=$(softwareupdate -l 2>/dev/null | grep -E '^[[:space:]]*\* Label: Command Line Tools' | sed 's/^.*Label: //' | sort | tail -n 1)
    if [[ -n "$label" ]]; then
        run "softwareupdate: $label" sudo softwareupdate -i "$label" --verbose
    fi
    rm -f "$marker"

    if ! xcode-select -p &>/dev/null; then
        warn "softwareupdate did not install them — falling back to the GUI installer"
        xcode-select --install 2>/dev/null || true
        info "finish the dialog that just opened; waiting…"
        until xcode-select -p &>/dev/null; do sleep 5; done
    fi
    success "installed at $(xcode-select -p)"
    return 0
}

step_clone() {
    # Running from inside a checkout? Use it.
    local here="" src="${BASH_SOURCE[0]:-}"
    # Under `bash -c "$(curl …)"` there is no script file — only a checkout run sets BASH_SOURCE.
    [[ -n "$src" && -f "$src" ]] && here="$(cd "$(dirname -- "$src")" 2>/dev/null && pwd)"
    if [[ -n "$here" && -f "$here/Brewfile" && -e "$here/.git" ]]; then
        dotfiles_path="$here"
        success "using this checkout: ${dotfiles_path/#$HOME/~}"
        return 0
    fi

    dotfiles_path=$(ask_input "Where should the dotfiles live?" "$dotfiles_path")
    if [[ -d "$dotfiles_path/.git" ]]; then
        success "already cloned at ${dotfiles_path/#$HOME/~}"
        run "git pull" git -C "$dotfiles_path" pull --ff-only || warn "could not fast-forward; using the checkout as is"
        return 0
    fi
    if [[ -e "$dotfiles_path" ]]; then
        fatal "$dotfiles_path exists and is not a git checkout. Move it away and re-run."
    fi
    run "git clone $DOTFILES_REPO" git clone "$DOTFILES_REPO" "$dotfiles_path" || fatal "clone failed"
    return 0
}

mas_ids() { grep -E '^mas ' "$dotfiles_path/Brewfile" | sed -E 's/.*id: *([0-9]+).*/\1/' | tr '\n' ' '; }

step_homebrew() {
    if ! ask_yes_no "Install Homebrew and everything in the Brewfile?"; then
        warn "skipped — most later steps need packages from the Brewfile"
        return 2
    fi

    load_brew
    if ! command -v brew &>/dev/null; then
        local installer
        installer="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || fatal "could not download the Homebrew installer"
        run "install Homebrew" env NONINTERACTIVE=1 /bin/bash -c "$installer" || fatal "Homebrew installation failed"
        load_brew
    else
        success "Homebrew $(brew --version | head -n 1 | awk '{print $2}') already installed"
        run "brew update" brew update || warn "brew update failed"
    fi
    command -v brew &>/dev/null || fatal "brew is not on PATH after installing"

    local total
    total=$(grep -cE '^(brew|cask|mas|tap|go|vscode) ' "$dotfiles_path/Brewfile")
    info "Brewfile: $total entries — this is the long part"

    if [[ $NO_MAS -eq 1 ]]; then
        export HOMEBREW_BUNDLE_MAS_SKIP
        HOMEBREW_BUNDLE_MAS_SKIP="$(mas_ids)"
        note "Mac App Store apps skipped (--no-mas)"
    elif grep -qE '^mas ' "$dotfiles_path/Brewfile"; then
        note "Mac App Store apps need an App Store login; failures can be retried with --only homebrew"
    fi

    if run "brew bundle" brew bundle --file "$dotfiles_path/Brewfile"; then
        success "every Brewfile entry is installed"
    else
        warn "some Brewfile entries failed:"
        grep -E "has failed!|^Error: " "$LOG" | tail -n 20 | strip_ansi | while IFS= read -r l; do note "    $l"; done
        followup "Retry failed Brewfile entries: brew bundle --file $dotfiles_path/Brewfile"
    fi
    return 0
}

# The bundle from `just secrets-export` on the old Mac: GPG, ~/.ssh and the age key. Importing it
# this early lets the GPG, SSH and GitHub steps (and the private hop/paw clones) use the real keys.
newest_bundle() {
    ls -t "$HOME"/Downloads/secrets-*.tar.gz.age "$HOME"/Desktop/secrets-*.tar.gz.age 2>/dev/null | head -n 1
}

step_secrets() {
    local key="$HOME/Library/Application Support/sops/age/keys.txt" f
    if [[ -f "$key" && -f "$HOME/.ssh/config" ]]; then
        success "age key and ~/.ssh already in place"
        return 0
    fi
    command -v age &>/dev/null || { warn "age is not installed (Brewfile step skipped?)"; return 2; }
    note "on the old Mac: cd ~/.dotfiles && just secrets-export — then AirDrop/USB the .age file here"
    if [[ $ASSUME_YES -eq 1 ]]; then
        note "needs the bundle passphrase — left for later"
        return 2
    fi
    if ! ask_yes_no "Import a secrets bundle now (GPG, SSH, age key)?"; then return 2; fi
    while true; do
        f=$(ask_input "Path to secrets-….tar.gz.age (empty to skip)" "$(newest_bundle)")
        f="${f/#\~/$HOME}"
        [[ -z "$f" ]] && return 2
        [[ -f "$f" ]] || { err "$f not found"; continue; }
        log_raw "  \$ secrets.sh import $f"
        # age asks for the passphrase on the terminal itself
        if DOTFILES="$dotfiles_path" bash "$dotfiles_path/scripts/secrets.sh" import "$f" </dev/tty; then
            success "secrets imported"
            if ask_yes_no "Delete $(basename "$f") now that it is imported?"; then rm -f "$f" && success "deleted"; fi
            return 0
        fi
        err "import failed"
        ask_yes_no "Try again?" || return 1
    done
}

step_shell() {
    local fish_path
    fish_path="$(command -v fish 2>/dev/null)" || true
    if [[ -z "$fish_path" ]]; then
        warn "fish is not installed (Brewfile step skipped?)"
        return 2
    fi

    if [[ "$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')" == "$fish_path" ]]; then
        success "fish is already the login shell"
    elif ask_yes_no "Make fish the login shell?"; then
        grep -qxF "$fish_path" /etc/shells || echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
        if sudo chsh -s "$fish_path" "$USER" >>"$LOG" 2>&1; then
            success "login shell → $fish_path"
        else
            err "chsh failed — run: chsh -s $fish_path"
        fi
    fi

    if ask_yes_no "Install Oh-My-Fish? (experimental)" "n"; then
        run "Oh-My-Fish" bash -c 'curl -fsSL https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install -o /tmp/omf-install && fish /tmp/omf-install --noninteractive --yes' \
            || warn "Oh-My-Fish install had issues"
    fi

    if ask_yes_no "Install Fisher + the plugins in fish/fish_plugins?"; then
        if run "Fisher" fish -c 'curl -fsSL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher'; then
            if [[ -f "$dotfiles_path/fish/fish_plugins" ]]; then
                ln -sfn "$dotfiles_path/fish/fish_plugins" "$HOME/.config/fish/fish_plugins"
                run "fisher plugins (fish/fish_plugins)" fish -c 'fisher update' || warn "Fisher plugins had issues"
            fi
        else
            warn "Fisher had issues"
        fi
    fi
    return 0
}

set_default_key() {
    local gpg_conf="$1" key_id="$2"
    if grep -q '^default-key' "$gpg_conf" 2>/dev/null; then
        sed -i '' "s/^default-key.*/default-key $key_id/" "$gpg_conf"
    else
        echo "default-key $key_id" >>"$gpg_conf"
    fi
    success "default key → $key_id"
}

step_gpg() {
    if ! ask_yes_no "Configure GPG (agent, pinentry-mac, signing key)?"; then return 2; fi
    mkdir -p ~/.gnupg && chmod 700 ~/.gnupg
    local agent=~/.gnupg/gpg-agent.conf conf=~/.gnupg/gpg.conf pin key_id f kind
    touch "$agent" "$conf"

    pin="$(command -v pinentry-mac 2>/dev/null || true)"
    if [[ -n "$pin" ]]; then
        grep -q '^pinentry-program' "$agent" || echo "pinentry-program $pin" >>"$agent"
        success "pinentry-mac configured"
    else
        warn "pinentry-mac not found"
    fi
    grep -qxF use-agent "$conf"       || echo use-agent >>"$conf"
    grep -qxF no-emit-version "$conf" || echo no-emit-version >>"$conf"
    gpgconf --kill gpg-agent 2>/dev/null || true
    success "gpg.conf: use-agent, no-emit-version"

    if ask_yes_no "Import keys from files?" "n"; then
        for kind in public private; do
            f=$(ask_input "Path to the $kind key (empty to skip)" "")
            [[ -z "$f" ]] && continue
            if [[ -f "$f" ]] && gpg --batch --import "$f" >>"$LOG" 2>&1; then success "$kind key imported"; else err "could not import $f"; fi
        done
        key_id=$(ask_input "Default signing key id" "$DEFAULT_GPG_KEY")
        [[ -n "$key_id" ]] && set_default_key "$conf" "$key_id"
    elif ask_yes_no "Generate a new key pair?" "n"; then
        if gpg --full-generate-key </dev/tty; then success "key generated"; else warn "key generation cancelled"; fi
        key_id=$(ask_input "Default signing key id" "")
        [[ -n "$key_id" ]] && set_default_key "$conf" "$key_id"
    else
        grep -q '^default-key' "$conf" || set_default_key "$conf" "$DEFAULT_GPG_KEY"
    fi
    if ! gpg --list-secret-keys "$DEFAULT_GPG_KEY" &>/dev/null; then
        followup "Import the GPG secret key $DEFAULT_GPG_KEY — .gitconfig signs every commit with it"
    fi
    return 0
}

step_ssh() {
    if ! ask_yes_no "Set up an SSH key?" "n"; then
        [[ -f ~/.ssh/id_ed25519 ]] || followup "No ~/.ssh/id_ed25519 — create or restore an SSH key"
        return 2
    fi
    local key="" email priv pub
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    if ask_yes_no "Generate a new ed25519 key?"; then
        email=$(ask_input "Email for the key" "urbanfoundit@gmail.com")
        key=$(ask_input "Key file" "$HOME/.ssh/id_ed25519")
        if [[ -f "$key" ]] && ! ask_yes_no "$key exists — overwrite?" "n"; then
            info "keeping the existing key"
        else
            ssh-keygen -t ed25519 -C "$email" -f "$key" </dev/tty && success "key written to ${key/#$HOME/~}"
        fi
    elif ask_yes_no "Import an existing key pair?" "n"; then
        priv=$(ask_input "Private key path" "")
        pub=$(ask_input "Public key path" "${priv}.pub")
        if [[ ! -f "$priv" || ! -f "$pub" ]]; then err "key files not found"; return 1; fi
        cp "$priv" ~/.ssh/ && chmod 600 ~/.ssh/"$(basename "$priv")"
        cp "$pub" ~/.ssh/ && chmod 644 ~/.ssh/"$(basename "$pub")"
        key=~/.ssh/"$(basename "$priv")"
        success "imported to ~/.ssh"
    else
        return 2
    fi
    [[ -f "$key" ]] || return 0

    if ! grep -q 'UseKeychain' ~/.ssh/config 2>/dev/null; then
        printf 'Host *\n  AddKeysToAgent yes\n  UseKeychain yes\n  IdentityFile %s\n' "$key" >>~/.ssh/config
        success "Keychain integration added to ~/.ssh/config"
    fi
    if ssh-add --apple-use-keychain "$key" </dev/tty >>"$LOG" 2>&1; then success "key added to the agent"; else warn "could not add the key to the agent"; fi
    if [[ -f "$key.pub" ]]; then
        info "public key — add it at https://github.com/settings/keys"
        note "    $(cat "$key.pub")"
    fi
    return 0
}

link() {
    local src="$1" dst="$2" name="$3"
    if [[ ! -e "$src" ]]; then
        warn "$name: ${src/#$HOME/~} is missing in the repo"
        return 1
    fi
    mkdir -p "$(dirname "$dst")"
    if [[ -f "$dst" && ! -L "$dst" ]] && { [[ ! -s "$dst" ]] || ! grep -qvE '^[[:space:]]*(#.*)?$|^if status is-interactive$|^end$' "$dst"; }; then
        rm -f "$dst"   # empty or fish's default config.fish stub — nothing worth a backup
    elif [[ -e "$dst" && ! -L "$dst" ]]; then
        mv "$dst" "$dst.backup-$(date +%Y%m%d-%H%M%S)"
        note "existing $name moved to ${dst/#$HOME/~}.backup-*"
    fi
    if ln -sfn "$src" "$dst"; then success "$name ${C_GREY}→ ${dst/#$HOME/~}${C_RESET}"; else err "$name link failed"; fi
}

link_each() {
    local src_dir="$1" dst_dir="$2" name="$3" f
    mkdir -p "$dst_dir"
    for f in "$src_dir"/*; do [[ -e "$f" ]] && ln -sfn "$f" "$dst_dir/"; done
    success "$name ${C_GREY}→ ${dst_dir/#$HOME/~}/${C_RESET}"
}

setup_sketchybar() {
    link "$dotfiles_path/sketchybar" "$HOME/.config/sketchybar" "sketchybar config"

    if [[ -f "$HOME/.local/share/sketchybar_lua/sketchybar.so" ]]; then
        success "SbarLua already installed"
    elif ! command -v lua &>/dev/null; then
        warn "lua missing (the Brewfile installs it) — SbarLua not built, the bar will not start"
    else
        local tmp
        tmp="$(mktemp -d)"
        run "build SbarLua" bash -c "git clone --depth 1 https://github.com/FelixKratz/SbarLua.git '$tmp/SbarLua' && cd '$tmp/SbarLua' && make install" \
            || warn "SbarLua build failed"
        rm -rf "$tmp"
    fi

    mkdir -p "$HOME/Library/Fonts"
    run "sketchybar app font $SKETCHYBAR_APP_FONT_VERSION" curl -fsSL -o "$HOME/Library/Fonts/sketchybar-app-font.ttf" \
        "https://github.com/kvndrsslr/sketchybar-app-font/releases/download/$SKETCHYBAR_APP_FONT_VERSION/sketchybar-app-font.ttf" \
        || warn "font download failed"
}

# hop/.env, hop/snippets.json5 and sketchybar/env.local.sh live in the repo only as sops-encrypted .enc copies.
# They decrypt with the age key, which arrives with `just secrets-import` (that decrypts them too).
decrypt_env() {
    local key="$HOME/Library/Application Support/sops/age/keys.txt"
    if [[ -f "$dotfiles_path/hop/.env" && -f "$dotfiles_path/hop/snippets.json5" && -f "$dotfiles_path/sketchybar/env.local.sh" ]]; then
        success "secret .env files already decrypted"
    elif [[ -f "$key" ]] && command -v sops &>/dev/null; then
        if bash "$dotfiles_path/scripts/env.sh" decrypt >>"$LOG" 2>&1; then
            success "decrypted hop/.env, hop/snippets.json5 and sketchybar/env.local.sh"
        else
            warn "the .env files did not decrypt (see the log)"
            followup "Decrypt the .env files: cd ~/.dotfiles && just decrypt"
        fi
    else
        note "no age key yet — hop bookmarks and the sketchybar gas item wait for the .env files"
        followup "After 'just secrets-import <file>' the .env files decrypt on their own (or: cd ~/.dotfiles && just decrypt)"
    fi
}

step_links() {
    if ! ask_yes_no "Link dotfiles into ~ (existing files are backed up)?"; then return 2; fi
    local d="$dotfiles_path"

    link "$d/.gitconfig"               "$HOME/.gitconfig"                       ".gitconfig"
    link "$d/starship.toml"            "$HOME/.config/starship.toml"            "starship"
    link "$d/ghostty/config"           "$HOME/.config/ghostty/config"           "ghostty"
    link "$d/pseudobun.fish"           "$HOME/.config/fish/pseudobun.fish"      "pseudobun.fish"
    link "$d/fish/config.fish"         "$HOME/.config/fish/config.fish"         "config.fish"
    link_each "$d/fish/conf.d"         "$HOME/.config/fish/conf.d"              "fish conf.d"
    link_each "$d/functions"           "$HOME/.config/fish/functions"           "fish functions"
    link "$d/fish/fish_plugins"        "$HOME/.config/fish/fish_plugins"        "fisher plugin list"
    [[ -d "$d/macchina" ]] && link "$d/macchina" "$HOME/.config/macchina" "macchina"

    mkdir -p "$HOME/repos/personal" "$HOME/repos/lutra"
    success "workspace folders ${C_GREY}→ ~/repos/personal, ~/repos/lutra${C_RESET}"

    setup_sketchybar
    link "$d/paw" "$HOME/.config/paw" "paw config"
    link "$d/hop" "$HOME/.config/hop" "hop config"
    decrypt_env

    # Hourly `brew outdated` refresh for the sketchybar brew item
    local agent="sh.pseudobun.brew-refresh"
    local plist="$HOME/Library/LaunchAgents/$agent.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    cp "$d/launchd/$agent.plist" "$plist"
    launchctl bootout "gui/$(id -u)/$agent" 2>/dev/null || true
    if launchctl bootstrap "gui/$(id -u)" "$plist" 2>>"$LOG"; then success "LaunchAgent $agent loaded"; else warn "LaunchAgent $agent did not load"; fi
    return 0
}

step_fish() {
    command -v fish &>/dev/null || { warn "fish is not installed"; return 2; }
    if ! ask_yes_no "Run setup.fish (PATH entries, omf theme if present, Fisher)?"; then return 2; fi
    run "setup.fish" fish "$dotfiles_path/setup.fish" || warn "setup.fish reported problems"
    return 0
}

step_devtools() {
    if ! ask_yes_no "Install development toolchains?"; then return 2; fi

    if command -v rustup &>/dev/null || [[ -x ~/.cargo/bin/rustup ]]; then
        success "Rust already installed"
    elif ask_yes_no "Rust (rustup)?"; then
        run "rustup" bash -c 'curl --proto =https --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path' || warn "rustup failed"
    fi

    if command -v bun &>/dev/null || [[ -x ~/.bun/bin/bun ]]; then
        success "Bun already installed"
    elif ask_yes_no "Bun?"; then
        run "bun" bash -c 'curl -fsSL https://bun.sh/install | bash' || warn "bun install failed"
    fi

    # pnpm, eas-cli and wscat come from the Brewfile's npm entries; fnm's node only needs corepack
    if command -v fnm &>/dev/null && ask_yes_no "Node 24 via fnm (default) + corepack?"; then
        run "fnm install 24" fnm install 24 && fnm default 24 >>"$LOG" 2>&1
        eval "$(fnm env --shell bash)" >/dev/null 2>&1
        run "corepack enable" corepack enable || warn "corepack failed"
    fi

    if [[ -x ~/.cargo/bin/cargo ]] && ask_yes_no "cargo extras (wasm-pack, cargo-generate)?" "n"; then
        run "cargo install" ~/.cargo/bin/cargo install wasm-pack cargo-generate || warn "cargo install failed"
    fi

    if ask_yes_no "Foundry (Ethereum)?" "n"; then
        run "foundryup" bash -c 'curl -fsSL https://foundry.paradigm.xyz | bash && ~/.foundry/bin/foundryup' || warn "foundry failed"
    fi
    if ask_yes_no "Deno?" "n"; then
        run "deno" bash -c 'curl -fsSL https://deno.land/install.sh | sh -s -- -y' || warn "deno failed"
    fi
    return 0
}

step_spicetify() {
    if ! ask_yes_no "Install Spicetify (Spotify theming)?" "n"; then return 2; fi
    run "spicetify cli" bash -c 'curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh' || warn "spicetify cli failed"
    run "spicetify marketplace" bash -c 'curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh' || warn "marketplace failed"
    return 0
}

step_macos() {
    if [[ $ROLE == server ]]; then
        note "dock · finder · input · dark mode (menu bar stays: no sketchybar on a server)"
    else
        note "menu bar hidden (sketchybar) · dock · finder · input · dark mode — same as sanctum"
    fi
    if ! ask_yes_no "Apply macOS defaults?"; then return 2; fi
    local w="defaults write"
    if [[ $ROLE == server ]]; then
        $w NSGlobalDomain _HIHideMenuBar -bool false
        if ask_yes_no "Never sleep, restart after a power cut, wake on LAN (pmset)?"; then
            if sudo pmset -a sleep 0 disksleep 0 autorestart 1 womp 1 >>"$LOG" 2>&1; then
                success "pmset: sleep 0, disksleep 0, autorestart 1, womp 1"
            else
                warn "pmset failed"
            fi
        fi
    else
        # menu bar: hidden, sketchybar replaces it
        $w NSGlobalDomain _HIHideMenuBar -bool true
    fi
    # dock
    $w com.apple.dock autohide -bool true
    $w com.apple.dock autohide-time-modifier -float 0.05
    $w com.apple.dock tilesize -int 56
    $w com.apple.dock mru-spaces -bool false          # keep spaces in order
    $w com.apple.dock scroll-to-open -bool true
    # spaces: one native Space per display (paw's workspaces replace them)
    $w com.apple.spaces spans-displays -bool false
    $w com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
    # finder
    $w com.apple.finder FXPreferredViewStyle -string Nlsv
    # input
    $w .GlobalPreferences com.apple.mouse.scaling -1
    $w NSGlobalDomain com.apple.swipescrolldirection -bool false
    $w NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
    # appearance
    $w NSGlobalDomain AppleInterfaceStyle -string Dark
    success "$([[ $ROLE == server ]] && echo "menu bar visible" || echo "menu bar hidden"), dock auto-hide 50 ms / size 56, fixed spaces, list view, no natural scroll, no autocorrect, dark"
    killall Dock Finder SystemUIServer 2>/dev/null || true
    note "some settings need a logout"
    return 0
}

step_terminal() {
    if ! ask_yes_no "Install Kitty?" "n"; then return 2; fi
    run "kitty" bash -c 'curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n' || warn "kitty failed"
    return 0
}

step_fonts() {
    note "JetBrains Mono + Roboto Mono from fonts/ (Nerd Fonts come from the Brewfile)"
    if ! ask_yes_no "Copy bundled fonts to ~/Library/Fonts?"; then return 2; fi
    mkdir -p "$HOME/Library/Fonts"
    local n=0 f
    while IFS= read -r -d '' f; do cp "$f" "$HOME/Library/Fonts/" && n=$((n + 1)); done \
        < <(find "$dotfiles_path/fonts" -type f \( -name '*.ttf' -o -name '*.otf' \) -print0)
    if (( n > 0 )); then success "$n font files installed"; else warn "no fonts found in fonts/"; fi
    return 0
}

step_iterm() {
    if [[ ! -d /Applications/iTerm.app ]]; then
        note "iTerm2 is not installed"
        return 2
    fi
    local d="$dotfiles_path"
    local todo="iTerm2: import itermcolors/DraculaPlus.itermcolors, profiles/pseudobun.json and profiles/pseudobun.itermkeymap"
    if ! ask_yes_no "Import the iTerm2 colours, profile and key map now?" "n"; then
        followup "$todo"
        return 2
    fi
    open -a iTerm "$d/itermcolors/DraculaPlus.itermcolors" 2>/dev/null || true
    info "colours opened in iTerm2; then import:"
    note "    Profiles › Other actions › Import JSON profiles › $d/profiles/pseudobun.json"
    note "    Keys › Key Bindings › Presets › Import › $d/profiles/pseudobun.itermkeymap"
    wait_for_manual_step || followup "$todo"
    return 0
}

step_github() {
    command -v gh &>/dev/null || { warn "gh is not installed"; return 2; }
    if gh auth status &>/dev/null; then
        success "already logged in as $(gh api user --jq .login 2>/dev/null)"
        return 0
    fi
    local default=y
    if github_ready; then
        success "the imported SSH key reaches GitHub (git clone works)"
        default=n
    fi
    if [[ $ASSUME_YES -eq 1 ]]; then
        note "interactive login — left for later"
        followup "Log in to GitHub: gh auth login"
        return 2
    fi
    if ask_yes_no "Log in to the GitHub CLI (gh) now?" "$default"; then
        if gh auth login </dev/tty; then success "logged in"; else warn "login cancelled"; fi
        return 0
    fi
    followup "Log in to GitHub: gh auth login"
    return 2
}

# hop (launcher) and paw (window manager) are private repos built from source
# into ~/repos/personal: they need a GitHub login (gh or an SSH key) first.
github_ready() {
    gh auth status &>/dev/null && return 0
    ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q 'successfully authenticated'
}

# install_from_source <name> <just recipe> — 0 installed/up to date, 1 failed, 2 not possible yet
install_from_source() {
    local name="$1" recipe="$2" dir="$HOME/repos/personal/$1" before="" after
    if [[ -d "$dir/.git" ]]; then
        before=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
        run "git pull $name" git -C "$dir" pull --ff-only || warn "$name: could not fast-forward; building the checkout as is"
    elif github_ready; then
        if gh auth status &>/dev/null; then
            run "clone pseudobun/$name" gh repo clone "pseudobun/$name" "$dir" || return 1
        else
            run "clone pseudobun/$name" git clone "git@github.com:pseudobun/$name.git" "$dir" || return 1
        fi
    else
        note "$name: pseudobun/$name is private and GitHub is not logged in yet"
        return 2
    fi
    after=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
    if [[ -n "$before" && "$before" == "$after" && -d "/Applications/$name.app" ]]; then
        success "$name is up to date"
        return 0
    fi
    # self-signed certificate, so the Accessibility grant survives rebuilds
    if ! security find-identity -p codesigning 2>/dev/null | grep -q "$name Local Signing"; then
        run "$name signing certificate" bash -c "cd '$dir' && just local-cert" || note "$name: no local certificate — ad-hoc signed, Accessibility resets on rebuilds"
    fi
    run "build + install $name" bash -c "cd '$dir' && just $recipe" || return 1
    return 0
}

# yabai, skhd, Hammerspoon (stackline) and Homerow are replaced by paw and hop: take them off
# a Mac that still has them, so nothing fights paw over windows or keys.
remove_legacy_wm() {
    local found=()
    command -v yabai &>/dev/null && found+=(yabai)
    command -v skhd &>/dev/null && found+=(skhd)
    [[ -d /Applications/Hammerspoon.app || -d "$HOME/.hammerspoon" ]] && found+=(Hammerspoon)
    [[ -d /Applications/Homerow.app ]] && found+=(Homerow)
    ls "$HOME/Library/LaunchAgents" 2>/dev/null | grep -qiE 'yabai|skhd' && found+=("yabai/skhd LaunchAgents")
    [[ -e /etc/sudoers.d/yabai ]] && found+=("yabai sudoers")
    (( ${#found[@]} )) || return 0
    if ! ask_yes_no "Remove ${found[*]} (paw and hop replace them)?"; then return 0; fi

    local agent
    for agent in "$HOME"/Library/LaunchAgents/*yabai*.plist "$HOME"/Library/LaunchAgents/*skhd*.plist; do
        [[ -e "$agent" ]] || continue
        launchctl bootout "gui/$(id -u)" "$agent" 2>/dev/null || true
        rm -f "$agent"
    done
    pkill -x yabai 2>/dev/null || true
    pkill -x skhd 2>/dev/null || true
    osascript -e 'quit app "Hammerspoon"' -e 'quit app "Homerow"' 2>/dev/null || true
    if command -v yabai &>/dev/null && [[ -d /Library/ScriptingAdditions/yabai.osax ]]; then
        run "remove yabai scripting addition" sudo yabai --uninstall-sa || true
    fi
    [[ -e /etc/sudoers.d/yabai ]] && { run "remove yabai sudoers rule" sudo rm -f /etc/sudoers.d/yabai || true; }
    local f
    for f in yabai skhd; do
        # tapped formulae (asmvik/formulae/yabai…) are often pinned
        brew list --formula "$f" &>/dev/null && { brew unpin "$f" 2>/dev/null; run "brew uninstall $f" brew uninstall --force "$f" || true; }
    done
    for f in hammerspoon homerow; do
        brew list --cask "$f" &>/dev/null && { run "brew uninstall --cask $f" brew uninstall --cask "$f" || true; }
    done
    rm -rf /Applications/Hammerspoon.app /Applications/Homerow.app 2>/dev/null || true
    rm -rf "$HOME/.hammerspoon" "$HOME/.config/yabai" "$HOME/.config/skhd" "$HOME/.yabairc" "$HOME/.skhdrc"
    success "removed ${found[*]}"
    if [[ "$(nvram boot-args 2>/dev/null)" == *arm64e_preview_abi* ]] || csrutil status 2>/dev/null | grep -q "Custom Configuration\|disabled"; then
        followup "yabai needed SIP partly off; paw doesn't: sudo nvram -d boot-args, then csrutil enable in Recovery"
    fi
}

# open_privacy_pane Accessibility — the exact System Settings pane (macOS 13+ URL, then the older one)
open_privacy_pane() {
    open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_$1" 2>/dev/null \
        || open "x-apple.systempreferences:com.apple.preference.security?Privacy_$1" 2>/dev/null
}

# grant_accessibility app… — start the apps so they show up in the list, open the pane, wait
grant_accessibility() {
    local todo="Grant Accessibility to $* (System Settings › Privacy & Security › Accessibility)" app
    if [[ $ASSUME_YES -eq 1 ]]; then followup "$todo"; return; fi
    for app in "$@"; do
        [[ -d "/Applications/$app.app" ]] && open -a "/Applications/$app.app" 2>/dev/null
    done
    open_privacy_pane Accessibility
    info "System Settings › Privacy & Security › Accessibility is open:"
    note "    turn on: $* (use + › /Applications if one is missing from the list)"
    if wait_for_manual_step; then
        for app in "$@"; do
            pgrep -xq "$app" || open -a "/Applications/$app.app" 2>/dev/null
        done
        success "Accessibility granted to $*"
    else
        followup "$todo"
    fi
}

step_apps() {
    local want_paw=y
    [[ $ROLE == server ]] && want_paw=n
    if ! ask_yes_no "Build and install hop (launcher)$([[ $want_paw == y ]] && echo " and paw (window manager)") from source?"; then return 2; fi
    command -v just &>/dev/null || { warn "just is not installed (Brewfile step skipped?)"; return 2; }
    local rc later=0 built=()

    remove_legacy_wm

    # both repos are private: log in here when the GitHub step was skipped or declined
    if ! github_ready && [[ $ASSUME_YES -eq 0 ]] && command -v gh &>/dev/null \
        && ask_yes_no "hop and paw are private repos — log in to GitHub now?"; then
        if gh auth login </dev/tty; then success "logged in to GitHub"; else warn "GitHub login cancelled"; fi
    fi

    # paw: SwiftPM — the Command Line Tools are enough. `just launchd` installs and starts it at login.
    if [[ $want_paw == y ]] || [[ -d "$HOME/repos/personal/paw/.git" ]]; then
        install_from_source paw launchd; rc=$?
        case $rc in 0) built+=(paw) ;; 2) later=1 ;; *) warn "paw failed" ;; esac
    else
        note "paw skipped (server role)"
    fi

    # hop: an Xcode project — needs the full Xcode (Mac App Store), not just the Command Line Tools
    if ! xcodebuild -version &>/dev/null && [[ ! -d /Applications/Xcode.app ]] && [[ $ASSUME_YES -eq 0 ]] \
        && command -v mas &>/dev/null && ask_yes_no "hop needs Xcode — install it from the App Store now (signed in to the App Store, ~12 GB)?" "n"; then
        run "Xcode (mas)" mas install 497799835 || warn "Xcode install failed — is the App Store signed in?"
    fi
    if [[ -d /Applications/Xcode.app ]] && ! xcodebuild -version &>/dev/null; then
        # a fresh Xcode still points xcode-select at the CLT and needs its licence and first launch
        run "select Xcode" sudo xcode-select -s /Applications/Xcode.app/Contents/Developer || true
        run "Xcode licence + first launch" bash -c 'sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch' || true
    fi
    if ! xcodebuild -version &>/dev/null; then
        note "hop needs Xcode (App Store) — only the Command Line Tools are here"
        followup "Install Xcode from the App Store, then build hop: ~/.dotfiles/bootstrap.sh --only apps"
        later=1
    else
        install_from_source hop install; rc=$?
        case $rc in 0) built+=(hop) ;; 2) later=1 ;; *) warn "hop failed" ;; esac
    fi

    if ! github_ready; then
        followup "Log in to GitHub (gh auth login, or import the SSH key), then build hop and paw: ~/.dotfiles/bootstrap.sh --only apps"
    fi
    (( ${#built[@]} )) && grant_accessibility "${built[@]}"
    (( ${#built[@]} == 0 && later == 1 )) && return 2
    return 0
}

step_services() {
    if ! ask_yes_no "Start sketchybar?" "$([[ $ROLE == server ]] && echo n || echo y)"; then return 2; fi

    if command -v sketchybar &>/dev/null; then
        run "sketchybar" brew services restart sketchybar || warn "sketchybar did not start"
    else
        warn "sketchybar is not installed"
    fi

    if command -v spicetify &>/dev/null && ask_yes_no "Apply Spicetify? (Spotify must have been opened once)" "n"; then
        run "spicetify apply" spicetify apply || warn "spicetify apply failed"
    fi
    return 0
}

# ============================================================================
# Driver
# ============================================================================

usage() { sed -n '3,25p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; }

list_steps() {
    local i
    for i in "${!STEP_IDS[@]}"; do
        printf '  %s%02d%s  %-10s %s\n' "$C_GOLD" "$((i + 1))" "$C_RESET" "${STEP_IDS[$i]}" "${STEP_TITLES[$i]}"
    done
}

summary() {
    local i total ok=0 warned=0 failed=0 skipped=0 icon colour
    total=$(( $(date +%s) - START_TS ))
    printf '\n  %s╭─%s %sSummary%s\n' "$C_GREY" "$C_RESET" "$C_BOLD" "$C_RESET"
    for i in "${!STEP_IDS[@]}"; do
        [[ -z "${STEP_STATUS[$i]:-}" ]] && continue
        case "${STEP_STATUS[$i]}" in
            done)    icon="✓"; colour="$C_GREEN"; ok=$((ok + 1)) ;;
            warn)    icon="!"; colour="$C_AMBER"; warned=$((warned + 1)) ;;
            skipped) icon="–"; colour="$C_GREY";  skipped=$((skipped + 1)) ;;
            *)       icon="✗"; colour="$C_RED";   failed=$((failed + 1)) ;;
        esac
        printf '  %s  %s%s%s  %-28s %s%8s%s\n' "$BAR" "$colour" "$icon" "$C_RESET" "${STEP_TITLES[$i]}" "$C_GREY" "$(fmt_duration "${STEP_TIME[$i]}")" "$C_RESET"
    done
    printf '  %s\n' "$BAR"
    printf '  %s  %s%d ok%s · %s%d warnings%s · %s%d failed%s · %d skipped · %s total\n' "$BAR" \
        "$C_GREEN" "$ok" "$C_RESET" "$C_AMBER" "$warned" "$C_RESET" "$C_RED" "$failed" "$C_RESET" "$skipped" "$(fmt_duration "$total")"
    log_raw "SUMMARY: $ok ok, $warned warnings, $failed failed, $skipped skipped, $(fmt_duration "$total")"
    if (( ${#FOLLOWUPS[@]} > 0 )); then
        printf '  %s\n' "$BAR"
        printf '  %s  %sStill to do by hand%s\n' "$BAR" "$C_BOLD" "$C_RESET"
        for i in "${!FOLLOWUPS[@]}"; do
            printf '  %s  %s□%s %s\n' "$BAR" "$C_AMBER" "$C_RESET" "${FOLLOWUPS[$i]}"
            log_raw "TODO: ${FOLLOWUPS[$i]}"
        done
    fi
    printf '  %s╰─%s log: %s\n\n' "$C_GREY" "$C_RESET" "${LOG/#$HOME/~}"
}

# laptop (sanctum) or server (olympus): --role, else the saved choice, else asked with a guess
resolve_role() {
    local guess=server
    pmset -g batt 2>/dev/null | grep -q InternalBattery && guess=laptop
    if [[ -z "$ROLE" && -f "$ROLE_FILE" ]]; then ROLE=$(<"$ROLE_FILE"); guess=$ROLE; ROLE=""; fi
    while [[ -z "$ROLE" ]]; do
        ROLE=$(ask_input "Role of this Mac — laptop (paw, sketchybar) or server (headless, hop only)?" "$guess")
        case "$ROLE" in laptop|server) ;; *) note "laptop or server"; ROLE="" ;; esac
    done
    mkdir -p "$(dirname "$ROLE_FILE")" && printf '%s\n' "$ROLE" >"$ROLE_FILE"
    log_raw "role: $ROLE"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)  ASSUME_YES=1 ;;
            --no-mas)  NO_MAS=1 ;;
            --role)    ROLE="${2:-}"; shift ;;
            --only)    ONLY="${2:-}"; shift ;;
            --skip)    SKIP="${2:-}"; shift ;;
            --list)    list_steps; exit 0 ;;
            -h|--help) usage; exit 0 ;;
            --)        ;;
            *)         printf 'unknown option: %s\n\n' "$1"; usage; exit 1 ;;
        esac
        shift
    done

    [[ "$(uname)" == "Darwin" ]] || fatal "macOS only."
    case "$ROLE" in laptop|server|"") ;; *) fatal "--role must be laptop or server" ;; esac
    mkdir -p "$(dirname "$LOG")"
    log_raw ""
    log_raw "################ bootstrap $(date '+%F %T') ################"

    resolve_role
    banner
    if [[ $ASSUME_YES -eq 0 ]]; then
        printf '\n'
        list_steps
        printf '\n'
        ask_yes_no "Start?" || exit 0
    fi
    printf '\n'
    sudo_keepalive

    local i id rc failed=0
    for i in "${!STEP_IDS[@]}"; do
        id="${STEP_IDS[$i]}"
        CURRENT=$i
        # clone always runs: every other step needs to know where the repo is
        if [[ -n "$ONLY" && "$id" != "clone" ]] && ! contains "$ONLY" "$id"; then continue; fi
        if [[ -n "$SKIP" ]] && contains "$SKIP" "$id"; then continue; fi
        step_begin
        "step_$id"; rc=$?
        load_brew
        case $rc in
            0) step_end done ;;
            2) step_end skipped ;;
            *) step_end failed; failed=1 ;;
        esac
    done

    # secrets travel separately: on the old machine `just secrets-export`, here `just secrets-import <file>`
    [[ -f "$HOME/Library/Application Support/sops/age/keys.txt" && -f "$HOME/.ssh/config" ]] \
        || followup "Secrets: on the old Mac run 'just secrets-export', copy the .age file here, then 'just secrets-import <file>' (GPG, SSH, age key; decrypts the .env files)"
    [[ -f "$HOME/Library/Application Support/sops/age/keys.txt" ]] \
        || followup "Restore the age key to ~/Library/Application Support/sops/age/keys.txt (sops / just decrypt)"
    [[ -f "$HOME/.ssh/config" ]] || followup "Restore ~/.ssh (keys + config with olympus/minsky/zeus hosts)"
    [[ -d "$HOME/.claude-config.git" ]] \
        || followup "Set up the ~/.claude sync: bare repo git@github.com:pseudobun/claude-config.git + LaunchAgent cloud.bunnys.claude-config-sync"
    if [[ $NO_MAS -eq 1 ]] && grep -qE '^mas ' "$dotfiles_path/Brewfile" 2>/dev/null; then
        followup "Sign in to the App Store, then: brew bundle --file $dotfiles_path/Brewfile (mas apps were skipped)"
    fi

    summary

    if [[ $ASSUME_YES -eq 0 ]]; then
        if ask_yes_no "Reboot now?" "n"; then sudo reboot; fi
        if command -v fish &>/dev/null && ask_yes_no "Open a fish shell?"; then exec fish -l; fi
    fi
    return $failed
}

# Run only when executed, not when sourced (tests source this file).
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main "$@"
fi
