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
#    --host sanctum|olympus
#                       which machine this is: hosts/<host>/ holds its Brewfile and the
#                       config files that differ (default: the last choice, else the hostname)
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
HOST=""
HOST_FILE="$HOME/.config/dotfiles/host"
HOSTS=(sanctum olympus)
REPOS_DIR="$HOME/repos/personal"   # olympus: flat ~/repos (set in resolve_host)
VAULT="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/obsidian"
VAULT_GIT_DIR="$HOME/git/bunny-os.git"
LOG="$HOME/Library/Logs/dotfiles-bootstrap.log"
START_TS=$(date +%s)
STEP_STARTED=$START_TS

STEP_IDS=(xcode clone homebrew secrets shell gpg ssh links fish devtools macos debloat github agents vault apps server services)
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
    "macOS defaults"
    "Debloat"
    "GitHub CLI login"
    "Agent config (Claude, Codex, opencode)"
    "Obsidian vault"
    "hop & paw"
    "olympus services"
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
    printf '  %sprofile%s %s   %smode%s %s   %slog%s %s\n' \
        "$C_GREY" "$C_RESET" "$HOST" \
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
    local started pid rc i=0 last now cols width dur
    started=$(date +%s)
    log_raw "  \$ $*"
    if [[ $IS_TTY -eq 1 ]]; then
        "$@" >>"$LOG" 2>&1 </dev/null &
        pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            now=$(( $(date +%s) - started ))
            # Room left on the line after "  │  ⠋ <label> <duration> · " (re-read: the window may resize).
            cols=$(stty size </dev/tty 2>/dev/null | cut -d' ' -f2)
            [[ "$cols" =~ ^[0-9]+$ ]] || cols=$(tput cols 2>/dev/null || echo 100)
            dur=$(fmt_duration "$now")
            width=$(( cols - ${#label} - ${#dur} - 12 ))
            # RUN_STATUS names a function that describes progress better than the last log line
            # (brew bundle prints every name up front); it is re-run once a second.
            if [[ -n "${RUN_STATUS:-}" ]]; then
                (( i % 10 == 0 )) && last=$("$RUN_STATUS" 2>/dev/null)
            else
                last=$(tail -n 1 "$LOG" 2>/dev/null | tr -d '\r' | strip_ansi | sed 's/^[[:space:]]*//')
            fi
            # Cut with an ellipsis rather than mid-word; drop it entirely when there is no room.
            if (( width < 8 )); then last=""
            elif (( ${#last} > width )); then last="${last:0:$((width - 1))}…"; fi
            printf '\r\033[K  %s  %s%s%s %s %s%s%s%s' "$BAR" "$C_WAVE" "${SPIN[$((i % 10))]}" "$C_RESET" "$label" \
                "$C_GREY" "$dur" "${last:+ · $last}" "$C_RESET"
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
    if [[ -n "$here" && -f "$here/bootstrap.sh" && -e "$here/.git" ]]; then
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

brewfile() { printf '%s\n' "$dotfiles_path/hosts/$HOST/Brewfile"; }

# brew bundle fetches everything first, then installs. Downloads include dependencies and
# manifests, so they are a plain file count; installs are counted against the Brewfile
# (dependencies count too, so that number is approximate and capped at the total).
brew_bundle_status() {
    local total dl inst prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"
    total=$(grep -cE '^(brew|cask) ' "$(brewfile)")
    dl=$(ls "$HOME/Library/Caches/Homebrew/downloads" 2>/dev/null | grep -vc '\.incomplete$')
    inst=$(( $(ls "$prefix/Cellar" 2>/dev/null | wc -l) + $(ls "$prefix/Caskroom" 2>/dev/null | wc -l) ))
    (( inst > total )) && inst=$total
    if (( inst > 0 )); then
        printf 'installed ~%d/%d' "$inst" "$total"
    else
        printf 'downloading · %d files' "$dl"
    fi
}

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

    local total free
    total=$(grep -cE '^(brew|cask|mas|tap|go|vscode|npm|cargo|uv) ' "$(brewfile)")
    info "hosts/$HOST/Brewfile: $total entries — this is the long part"

    # A full sanctum Brewfile peaks at ~60 GB (apps + Cellar + download cache); a full disk
    # breaks every later step, the log included.
    free=$(df -g "$HOME" 2>/dev/null | awk 'NR == 2 { print $4 }')
    if [[ "$free" =~ ^[0-9]+$ ]] && (( free < 70 )); then
        warn "only ${free} GB free — the Brewfile needs ~60 GB at its peak (in a Tart VM: tart set <vm> --disk-size 150)"
        ask_yes_no "Continue anyway?" || return 1
    fi

    if [[ $NO_MAS -eq 1 ]]; then
        export HOMEBREW_BUNDLE_MAS_SKIP
        HOMEBREW_BUNDLE_MAS_SKIP="$(mas_ids)"
        note "Mac App Store apps skipped (--no-mas)"
    elif grep -qE '^mas ' "$(brewfile)"; then
        note "Mac App Store apps need an App Store login; failures can be retried with --only homebrew"
    fi

    if RUN_STATUS=brew_bundle_status run "brew bundle" brew bundle --file "$(brewfile)"; then
        success "every Brewfile entry is installed"
    else
        warn "some Brewfile entries failed:"
        grep -E "has failed!|^Error: " "$LOG" | tail -n 20 | strip_ansi | while IFS= read -r l; do note "    $l"; done
        followup "Retry failed Brewfile entries: brew bundle --file $(brewfile)"
    fi
    # The download cache is ~20 GB after a full Brewfile and nothing reuses it.
    run "brew cleanup" brew cleanup --prune=all -s || warn "brew cleanup failed"
    grep -q '^# Not in Homebrew' "$(brewfile)" && followup "Apps outside Homebrew: see the end of hosts/$HOST/Brewfile"
    [[ $HOST == sanctum ]] && install_cutter
    return 0
}

# Cutter (reverse engineering, used with REA) is not notarized: macOS cancels mounting its
# quarantined DMG, so `brew install --cask cutter` fails. Fetch with brew, drop the quarantine,
# mount and copy it ourselves.
install_cutter() {
    if [[ -d /Applications/Cutter.app ]]; then success "Cutter already installed"; return 0; fi
    local dmg mnt
    dmg=$(brew --cache --cask cutter)
    run "fetch Cutter" brew fetch --cask cutter || { warn "Cutter download failed"; return 0; }
    xattr -c "$dmg"
    mnt=$(mktemp -d)
    if diskutil image attach --mountOptions nobrowse --readOnly --mountPoint "$mnt" "$dmg" >>"$LOG" 2>&1 \
        && ditto "$mnt/Cutter.app" /Applications/Cutter.app; then
        xattr -dr com.apple.quarantine /Applications/Cutter.app
        success "Cutter ${C_GREY}→ /Applications${C_RESET}"
    else
        warn "Cutter did not install (see the log)"
    fi
    hdiutil detach "$mnt" -quiet 2>/dev/null
    rmdir "$mnt" 2>/dev/null
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

    # The secrets bundle (step secrets) normally brings the key; only ask when it did not.
    if gpg --list-secret-keys "$DEFAULT_GPG_KEY" &>/dev/null; then
        success "signing key $DEFAULT_GPG_KEY is in the keyring"
        grep -q '^default-key' "$conf" || set_default_key "$conf" "$DEFAULT_GPG_KEY"
        return 0
    fi
    note "no secret key $DEFAULT_GPG_KEY — the secrets bundle brings it; import armored .asc files only without one"
    if ask_yes_no "Import keys from .asc files?" "n"; then
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
    # The secrets bundle (step secrets) normally brings the key; don't offer to replace it.
    if [[ -f ~/.ssh/id_ed25519 ]]; then
        success "~/.ssh/id_ed25519 is in place"
        return 0
    fi
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
            rm -f "$key" "$key.pub"   # already confirmed — keep ssh-keygen from asking again
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

# link_config <dir> <dest> <name> — ~/.config/<x> → the repo's <dir>. When hosts/$HOST/<dir> exists,
# <dest> becomes a real folder: each shared file is linked, then the host's own files replace theirs.
link_config() {
    local dir="$1" dst="$2" name="$3" src="$dotfiles_path/$1" over="$dotfiles_path/hosts/$HOST/$1" f b
    if [[ ! -d "$over" ]]; then link "$src" "$dst" "$name"; return; fi
    [[ -L "$dst" ]] && rm -f "$dst"
    mkdir -p "$dst"
    for f in "$src"/* "$src"/.[!.]* "$over"/* "$over"/.[!.]*; do
        [[ -e "$f" ]] || continue
        b=$(basename "$f")
        # a host file wins over the shared one
        [[ "$f" == "$src/"* && -e "$over/$b" ]] && continue
        if [[ -e "$dst/$b" && ! -L "$dst/$b" ]]; then
            mv "$dst/$b" "$dst/$b.backup-$(date +%Y%m%d-%H%M%S)"
            note "existing $name/$b moved to ${dst/#$HOME/~}/$b.backup-*"
        fi
        ln -sfn "$f" "$dst/$b"
    done
    success "$name ${C_GREY}→ ${dst/#$HOME/~} (shared + hosts/$HOST/$dir)${C_RESET}"
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
    link "$d/mise/config.toml"         "$HOME/.config/mise/config.toml"         "mise (global tool versions)"
    link "$d/ghostty/config"           "$HOME/.config/ghostty/config"           "ghostty"
    link "$d/pseudobun.fish"           "$HOME/.config/fish/pseudobun.fish"      "pseudobun.fish"
    link "$d/fish/config.fish"         "$HOME/.config/fish/config.fish"         "config.fish"
    link_each "$d/fish/conf.d"         "$HOME/.config/fish/conf.d"              "fish conf.d"
    link "$d/fish/fish_plugins"        "$HOME/.config/fish/fish_plugins"        "fisher plugin list"
    link "$d/zsh/zshrc"                "$HOME/.zshrc"                           ".zshrc (mirror of the fish setup)"

    if [[ $HOST == olympus ]]; then
        mkdir -p "$HOME/repos"
        success "workspace folder ${C_GREY}→ ~/repos (flat)${C_RESET}"
    else
        mkdir -p "$HOME/repos/personal" "$HOME/repos/lutra"
        success "workspace folders ${C_GREY}→ ~/repos/personal, ~/repos/lutra${C_RESET}"
    fi

    setup_sketchybar
    decrypt_env
    link_config paw "$HOME/.config/paw" "paw config"
    link_config hop "$HOME/.config/hop" "hop config"
    # With host overrides ~/.config/hop is a real folder: link hop's secret files by name too, so they
    # work once `just secrets-import` / `just decrypt` creates them later (a dangling link is harmless).
    if [[ -d "$HOME/.config/hop" && ! -L "$HOME/.config/hop" ]]; then
        local s
        for s in .env snippets.json5; do
            [[ -e "$HOME/.config/hop/$s" && ! -L "$HOME/.config/hop/$s" ]] || ln -sfn "$d/hop/$s" "$HOME/.config/hop/$s"
        done
    fi

    # brew-refresh: hourly `brew outdated` for the sketchybar brew item
    # shell-env: SHELL=fish for GUI apps (T3 Code terminals and agents, editors)
    local agent plist
    mkdir -p "$HOME/Library/LaunchAgents"
    for agent in sh.pseudobun.brew-refresh sh.pseudobun.shell-env; do
        plist="$HOME/Library/LaunchAgents/$agent.plist"
        cp "$d/launchd/$agent.plist" "$plist"
        launchctl bootout "gui/$(id -u)/$agent" 2>/dev/null || true
        if launchctl bootstrap "gui/$(id -u)" "$plist" 2>>"$LOG"; then success "LaunchAgent $agent loaded"; else warn "LaunchAgent $agent did not load"; fi
    done
    return 0
}

step_fish() {
    command -v fish &>/dev/null || { warn "fish is not installed"; return 2; }
    if ! ask_yes_no "Run setup.fish (PATH entries, Fisher)?"; then return 2; fi
    run "setup.fish" fish "$dotfiles_path/setup.fish" || warn "setup.fish reported problems"
    return 0
}

step_devtools() {
    if ! ask_yes_no "Install development toolchains?"; then return 2; fi

    # mise/config.toml: the JVM (Java 21 for Ghidra). Node stays on fnm.
    if command -v mise &>/dev/null; then
        run "mise install (Java)" mise install || warn "mise install failed"
    fi

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
    return 0
}

step_macos() {
    note "menu bar hidden (sketchybar) · dock · finder · input · dark mode"
    if ! ask_yes_no "Apply macOS defaults?"; then return 2; fi
    local w="defaults write"
    # menu bar: hidden, sketchybar replaces it
    $w NSGlobalDomain _HIHideMenuBar -bool true
    $w com.apple.controlcenter AutoHideMenuBarOption -int 0   # macOS 15+: "always" auto-hide
    # dock
    $w com.apple.dock autohide -bool true
    # paw tiles: no macOS edge / ⌥-drag tiling (its outlines show next to paw's drop preview)
    $w com.apple.WindowManager EnableTilingByEdgeDrag -bool false
    $w com.apple.WindowManager EnableTopTilingByEdgeDrag -bool false
    $w com.apple.WindowManager EnableTilingOptionAccelerator -bool false
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
    $w NSGlobalDomain com.apple.trackpad.scaling -float 1.5
    $w NSGlobalDomain com.apple.swipescrolldirection -bool false
    $w NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
    $w NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
    $w NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
    # trackpad: no three-finger Look Up tap (hop rings can use tap3)
    $w com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -int 0
    $w com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerTapGesture -int 0
    # hot corners: none (bottom right is Quick Note by default)
    $w com.apple.dock wvous-br-corner -int 1
    $w com.apple.dock wvous-br-modifier -int 0
    # appearance
    $w NSGlobalDomain AppleInterfaceStyle -string Dark
    success "menu bar hidden, dock auto-hide 50 ms / size 56, fixed spaces, list view, no natural scroll, no autocorrect, dark"
    set_wallpaper
    killall Dock Finder SystemUIServer 2>/dev/null || true
    note "some settings need a logout"
    return 0
}

# The bunny wallpaper on every display: portrait displays get the portrait one.
set_wallpaper() {
    local land="$dotfiles_path/wallpapers/bunny-4k-landscape.png" port="$dotfiles_path/wallpapers_portrait/bunny-4k-portrait.png"
    [[ -f "$land" && -f "$port" ]] || { warn "wallpapers missing in the repo"; return 0; }
    if osascript -l JavaScript - "$land" "$port" >>"$LOG" 2>&1 <<'JXA'
ObjC.import('AppKit')
function run(argv) {
  const ws = $.NSWorkspace.sharedWorkspace, screens = $.NSScreen.screens
  for (let i = 0; i < screens.count; i++) {
    const s = screens.objectAtIndex(i), f = s.frame
    const url = $.NSURL.fileURLWithPath(f.size.height > f.size.width ? argv[1] : argv[0])
    ws.setDesktopImageURLForScreenOptionsError(url, s, $({}), null)
  }
}
JXA
    then success "wallpaper set on every display"; else warn "wallpaper not set (see the log)"; fi
}

# Apple's extra apps live on the sealed system volume (/System/Applications): macOS refuses to
# delete them while SIP is on and puts them back with every update — so they leave the Dock.
DEBLOAT_APPS=(News Books Chess "Photo Booth" Podcasts Tips Games)

step_debloat() {
    note "${DEBLOAT_APPS[*]}: sealed system apps — macOS does not allow deleting them, they leave the Dock"
    if ! ask_yes_no "Debloat: take them off the Dock and auto-hide the Dock?"; then return 2; fi
    defaults write com.apple.dock autohide -bool true
    if command -v dockutil &>/dev/null; then
        local app removed=()
        for app in "${DEBLOAT_APPS[@]}"; do
            dockutil --find "$app" &>/dev/null || continue
            dockutil --remove "$app" --no-restart >>"$LOG" 2>&1 && removed+=("$app")
        done
        if (( ${#removed[@]} )); then success "off the Dock: ${removed[*]}"; else success "none of them is in the Dock"; fi
    else
        warn "dockutil is missing (Brewfile) — the Dock was not cleaned"
    fi
    killall Dock 2>/dev/null || true
    success "Dock auto-hides"
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

# Every coding agent reads the same global instructions: ~/.claude/CLAUDE.md, synced between the
# Macs by pseudobun/claude-config (bare repo ~/.claude-config.git, launchd every 10 min).
AGENT_INSTRUCTION_LINKS=(".codex/AGENTS.md" ".config/opencode/AGENTS.md")

link_agent_instructions() {
    local f
    for f in "${AGENT_INSTRUCTION_LINKS[@]}"; do
        mkdir -p "$HOME/$(dirname "$f")"
        [[ "$(readlink "$HOME/$f")" == "$HOME/.claude/CLAUDE.md" ]] && continue
        [[ -e "$HOME/$f" && ! -L "$HOME/$f" ]] && mv "$HOME/$f" "$HOME/$f.backup-$(date +%Y%m%d-%H%M%S)"
        ln -sfn "$HOME/.claude/CLAUDE.md" "$HOME/$f"
    done
    success "~/.codex/AGENTS.md and ~/.config/opencode/AGENTS.md → ~/.claude/CLAUDE.md"
}

step_agents() {
    if ! ask_yes_no "Set up the synced agent config (~/.claude + AGENTS.md for Codex and opencode)?"; then return 2; fi
    # Claude Code: Anthropic's native installer (~/.local/bin/claude, updates itself). The Homebrew
    # cask lags behind and does not auto-update. Codex and opencode come from the Brewfile.
    if [[ -x "$HOME/.local/bin/claude" ]]; then
        success "Claude Code already installed ${C_GREY}($("$HOME/.local/bin/claude" --version 2>/dev/null | head -1))${C_RESET}"
    elif run "Claude Code (native installer)" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'; then
        success "Claude Code ${C_GREY}→ ~/.local/bin/claude${C_RESET}"
        followup "Log in to Claude Code: run claude, then /login"
    else
        warn "Claude Code did not install"; followup "Install Claude Code: curl -fsSL https://claude.ai/install.sh | bash"
    fi
    if [[ -d "$HOME/.claude-config.git" ]]; then
        success "claude-config already checked out"
    elif github_ready; then
        if gh auth status &>/dev/null; then
            run "clone pseudobun/claude-config" gh repo clone pseudobun/claude-config "$HOME/.claude-config.git" -- --bare || return 1
        else
            run "clone pseudobun/claude-config" git clone --bare git@github.com:pseudobun/claude-config.git "$HOME/.claude-config.git" || return 1
        fi
        # its own bootstrap checks the config out into ~ (backing up what it replaces) and starts the sync agent
        run "claude-config checkout + sync agent" bash -c 'cd ~ && git --git-dir="$HOME/.claude-config.git" show main:.claude-config/bootstrap.sh | bash' || return 1
    else
        note "pseudobun/claude-config is private and GitHub is not logged in yet"
        followup "Log in to GitHub, then: ~/.dotfiles/bootstrap.sh --only agents (claude-config, REA, Ghidra)"
        return 2
    fi
    if [[ -f "$HOME/.claude/CLAUDE.md" ]]; then link_agent_instructions; else warn "~/.claude/CLAUDE.md is missing after the checkout"; fi
    # The REA skill comes with claude-config; its MCP server lives in ~/.claude.json, which is not synced.
    export PATH="$HOME/.local/bin:$PATH"   # a claude installed a moment ago
    if command -v npx &>/dev/null && command -v claude &>/dev/null; then
        install_ghidra
        rea_setup
    else
        warn "npx or claude missing: REA and Ghidra skipped"
        followup "REA + Ghidra: ~/.dotfiles/bootstrap.sh --only agents"
    fi
    return 0
}

# REA's own setup (https://github.com/morluto/rea): MCP for Claude Code and Codex, plus its skill.
# Its skill dirs must be real folders, not links. Setup keeps server env overrides, so the Ghidra
# paths are added afterwards (Claude: re-add with -e; Codex: an [mcp_servers.rea.env] table).
rea_setup() {
    local skill="$HOME/.claude/skills/reverse-engineer-anything" codex="$HOME/.codex/config.toml" args
    [[ -L "$skill" ]] && rm -f "$skill"
    if ! run "REA setup (Claude Code, Codex, skill)" npx -y rea-agents@latest setup --client claude_code --client codex --yes; then
        warn "REA setup failed (see the log)"; return 1
    fi
    args=$(claude mcp get rea 2>/dev/null | sed -n 's/^  Args: //p')
    claude mcp remove --scope user rea &>/dev/null || true
    # shellcheck disable=SC2086
    run "REA MCP env for Claude Code" claude mcp add --scope user rea \
        -e GHIDRA_INSTALL_DIR="$HOME/opt/ghidra" -e JAVA_HOME="$GHIDRA_JAVA_HOME" -- npx ${args:--y rea-agents@latest mcp} \
        || warn "REA MCP env for Claude Code not set"
    if [[ -f "$codex" ]] && grep -q '^\[mcp_servers.rea\]' "$codex" && ! grep -q '^\[mcp_servers.rea.env\]' "$codex"; then
        printf '\n[mcp_servers.rea.env]\nGHIDRA_INSTALL_DIR = "%s"\nJAVA_HOME = "%s"\n' "$HOME/opt/ghidra" "$GHIDRA_JAVA_HOME" >>"$codex"
    fi
    success "REA ${C_GREY}→ Claude Code + Codex, Ghidra $GHIDRA_VERSION${C_RESET}"
}

# Ghidra for REA, which accepts only the 12.1 line (verified 12.1.4) on Java 21. Homebrew ships 12.2,
# so the release zip goes to ~/opt (link ~/opt/ghidra); the release has no macOS arm64 natives
# (decompiler, sleigh), so they are built once with Ghidra's own Gradle wrapper.
GHIDRA_VERSION=12.1.4
GHIDRA_ZIP=ghidra_12.1.4_PUBLIC_20260921.zip
GHIDRA_SHA256=ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db
GHIDRA_JAVA_HOME="$HOME/.local/share/mise/installs/java/temurin-21"
install_ghidra() {
    local dir="$HOME/opt/ghidra_${GHIDRA_VERSION}_PUBLIC" tmp
    command -v mise &>/dev/null && mise install java >>"$LOG" 2>&1
    if [[ ! -x "$dir/support/analyzeHeadless" ]]; then
        tmp=$(mktemp -d)
        if ! run "download Ghidra $GHIDRA_VERSION" curl -fsSL -o "$tmp/$GHIDRA_ZIP" \
            "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/$GHIDRA_ZIP"; then
            warn "Ghidra download failed"; return 1
        fi
        if ! echo "$GHIDRA_SHA256  $tmp/$GHIDRA_ZIP" | shasum -a 256 -c - >>"$LOG" 2>&1; then
            warn "Ghidra download does not match its SHA-256; not installed"; return 1
        fi
        mkdir -p "$HOME/opt" && ditto -x -k "$tmp/$GHIDRA_ZIP" "$HOME/opt/"
        rm -rf "$tmp"
    fi
    ln -sfn "$dir" "$HOME/opt/ghidra"
    if [[ ! -x "$dir/Ghidra/Features/Decompiler/build/os/mac_arm_64/decompile" ]]; then
        run "build Ghidra natives (decompiler, sleigh)" bash -c "cd '$dir/support/gradle' && JAVA_HOME='$GHIDRA_JAVA_HOME' ./gradlew -q buildNatives" \
            || { warn "Ghidra natives did not build (needs the Command Line Tools)"; return 1; }
    fi
    success "Ghidra $GHIDRA_VERSION ${C_GREY}→ ~/opt/ghidra${C_RESET}"
}

# The Obsidian vault lives in iCloud Drive. olympus keeps it downloaded (agents read it, qmd indexes it)
# and is the only Mac with its git repo: a separate git dir at ~/git/bunny-os.git, never in iCloud.
vault_download() {
    find "$VAULT" -type f -not -path '*/.obsidian/*' -print0 2>/dev/null | xargs -0 -n 20 brctl download 2>>"$LOG"
}

step_vault() {
    if [[ ! -d "$VAULT" ]]; then
        note "no Obsidian vault yet — it comes with iCloud Drive (Apple Account › iCloud › iCloud Drive)"
        if [[ $ASSUME_YES -eq 0 ]] && ask_yes_no "Sign in to iCloud now?"; then
            open "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings" 2>/dev/null || open -b com.apple.systempreferences
            info "sign in, turn on iCloud Drive, then wait until Finder › iCloud Drive › Obsidian shows up"
            wait_for_manual_step
        fi
        if [[ ! -d "$VAULT" ]]; then
            followup "Sign in to iCloud (iCloud Drive on), let the vault sync, then: ~/.dotfiles/bootstrap.sh --only vault"
            return 2
        fi
    fi
    if [[ $HOST != olympus ]]; then
        success "vault is in iCloud (its git repo and qmd live on olympus only)"
        return 0
    fi
    if ! ask_yes_no "Keep the vault downloaded, set up its git repo and the qmd index?"; then return 2; fi
    # Optimize Mac Storage evicts files to placeholders that agents cannot read
    defaults write com.apple.bird optimize-storage -bool false
    vault_download
    success "iCloud Drive keeps files on disk; vault download requested"

    if [[ -d "$VAULT_GIT_DIR" ]]; then
        success "vault git dir already at ${VAULT_GIT_DIR/#$HOME/~}"
    elif github_ready; then
        local url=https://github.com/pseudobun/bunny-os.git
        gh auth status &>/dev/null || url=git@github.com:pseudobun/bunny-os.git
        mkdir -p "$(dirname "$VAULT_GIT_DIR")"
        run "clone pseudobun/bunny-os" git clone --bare "$url" "$VAULT_GIT_DIR" || return 1
        vgit() { git --git-dir="$VAULT_GIT_DIR" --work-tree="$VAULT" "$@"; }
        vgit config core.bare false
        vgit config remote.origin.url https://github.com/pseudobun/bunny-os.git
        vgit config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
        run "fetch bunny-os" vgit fetch -q origin || true
        vgit branch -q --set-upstream-to=origin/main main 2>>"$LOG" || true
        # build the index from HEAD without touching the files iCloud brought
        vgit reset -q 2>>"$LOG"
        success "vault git dir → ${VAULT_GIT_DIR/#$HOME/~}"
    else
        note "pseudobun/bunny-os is private and GitHub is not logged in yet"
        followup "Log in to GitHub, then: ~/.dotfiles/bootstrap.sh --only vault"
    fi
    # the pointer file syncs through iCloud; write it if it has not arrived
    [[ -f "$VAULT/.git" ]] || printf 'gitdir: %s\n' "$VAULT_GIT_DIR" >"$VAULT/.git"

    if command -v qmd &>/dev/null; then
        qmd collection show bunny-os &>/dev/null \
            || run "qmd collection bunny-os" qmd collection add "$VAULT" --name bunny-os --mask '**/*.md' || true
        run "qmd update" qmd update || warn "qmd update failed"
        run "qmd embed" qmd embed || warn "qmd embed failed"
    else
        warn "qmd is not installed (npm @tobilu/qmd in the Brewfile)"
    fi
    return 0
}

# GitHub login (gh or an SSH key), for the private clones and the agent config.
github_ready() {
    gh auth status &>/dev/null && return 0
    ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q 'successfully authenticated'
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
    note "    first confirm macOS's \"downloaded from the Internet\" dialog for each app (Open)"
    note "    then turn on: $* (use + › /Applications if one is missing from the list)"
    if wait_for_manual_step; then
        # restart them: an app started before the grant does not pick up the windows that are already open
        for app in "$@"; do
            [[ $app == paw ]] && { timeout 10 paw quit 2>/dev/null || true; }
            # by path: `pkill -x paw` would also end CLI runs such as sketchybar's `paw subscribe`
            pkill -f "/Applications/$app.app/Contents/MacOS/$app\$" 2>/dev/null; sleep 1
            open -a "/Applications/$app.app" 2>/dev/null
        done
        if command -v paw &>/dev/null && [[ " $* " == *" paw "* ]]; then
            sleep 2
            if timeout 10 paw status 2>/dev/null | grep -q 'trusted: yes'; then success "paw is trusted"; else warn "paw is still not trusted — toggle it off and on in Accessibility"; fi
        fi
        success "Accessibility granted to $*"
    else
        followup "$todo"
    fi
}

step_apps() {
    # Signed, notarized releases from pseudobun/tap (the Brewfiles list both casks too); they update
    # themselves. To work on one: clone it and `just dev` builds a separate "hop Dev" / "paw Dev".
    if ! ask_yes_no "Install hop (launcher) and paw (window manager) from Homebrew?"; then return 2; fi
    local app missing=() casks=()

    remove_legacy_wm

    for app in paw hop; do
        brew list --cask "pseudobun/tap/$app" &>/dev/null || missing+=("$app")
    done
    if (( ${#missing[@]} == 0 )); then
        success "hop and paw are installed from Homebrew (they update themselves)"
    else
        for app in "${missing[@]}"; do
            # an old build from source in /Applications blocks the cask
            if [[ -d "/Applications/$app.app" ]]; then
                note "/Applications/$app.app is not from Homebrew (an old build from source) — moving it to the Trash"
                [[ $app == paw ]] && { timeout 10 paw quit 2>/dev/null || true; }
                pkill -f "/Applications/$app.app/Contents/MacOS/$app\$" 2>/dev/null; sleep 1
                mv "/Applications/$app.app" "$HOME/.Trash/$app-from-source-$(date +%s).app" || return 1
                [[ -L "$(brew --prefix)/bin/$app" ]] && rm -f "$(brew --prefix)/bin/$app"
            fi
            casks+=("pseudobun/tap/$app")
        done
        run "brew install --cask ${missing[*]}" brew install --cask "${casks[@]}" || { warn "brew install failed"; return 1; }
    fi
    local need=()
    timeout 10 paw status 2>/dev/null | grep -q 'trusted: yes' || need+=(paw)
    timeout 10 hop permissions 2>/dev/null | grep -qE '^Accessibility[[:space:]]+granted' || need+=(hop)
    if (( ${#need[@]} )); then grant_accessibility "${need[@]}"; else success "hop and paw have Accessibility"; fi
    return 0
}

# olympus: the always-on box — power settings, its service repos, LaunchAgents, cron jobs, Docker.
step_server() {
    if [[ $HOST != olympus ]]; then note "olympus only"; return 2; fi
    if ! ask_yes_no "Set up the olympus services (power, repos, LaunchAgents, cron, Docker)?"; then return 2; fi
    local repo name plist label f

    if ask_yes_no "Never sleep, restart after a power cut, wake on LAN (pmset)?"; then
        if sudo pmset -a sleep 0 disksleep 0 autorestart 1 womp 1 >>"$LOG" 2>&1; then
            success "pmset: sleep 0, disksleep 0, autorestart 1, womp 1"
        else
            warn "pmset failed"
        fi
    fi

    while IFS= read -r repo; do
        [[ -z "$repo" || "$repo" == \#* ]] && continue
        name="${repo##*/}"
        if [[ -d "$HOME/repos/$name/.git" ]]; then
            success "$repo already in ~/repos/$name"
        elif github_ready; then
            if gh auth status &>/dev/null; then
                run "clone $repo" gh repo clone "$repo" "$HOME/repos/$name" || warn "$repo did not clone"
            else
                run "clone $repo" git clone "git@github.com:$repo.git" "$HOME/repos/$name" || warn "$repo did not clone"
            fi
        else
            followup "Log in to GitHub, then: ~/.dotfiles/bootstrap.sh --only server (clones $repo)"
        fi
    done <"$dotfiles_path/hosts/olympus/repos.txt"

    mkdir -p "$HOME/Library/LaunchAgents"
    for plist in "$HOME"/repos/olympus-dashboard/scripts/launchd/*.plist "$dotfiles_path"/hosts/olympus/launchd/*.plist; do
        [[ -f "$plist" ]] || continue
        label=$(basename "$plist" .plist)
        if [[ $label == cloud.bunnys.adguardhome && ! -x "$HOME/opt/adguardhome/AdGuardHome" ]]; then
            followup "Restore ~/opt/adguardhome (binary + data/AdGuardHome.yaml) from the backup, then: ~/.dotfiles/bootstrap.sh --only server"
            continue
        fi
        cp "$plist" "$HOME/Library/LaunchAgents/$label.plist"
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
        if launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$label.plist" 2>>"$LOG"; then
            success "LaunchAgent $label"
        else
            warn "LaunchAgent $label did not load"
        fi
    done
    followup "Full Disk Access for /opt/homebrew/bin/just (vault-mirror reads iCloud Drive at night)"
    [[ -f "$HOME/Library/LaunchAgents/com.t3tools.t3code.service.plist" ]] \
        || followup "Install the T3 Code service (agents run through it; LaunchAgent com.t3tools.t3code.service)"

    # cron: the security monitors install their own crontab lines (other lines stay)
    for f in "$HOME"/repos/olympus-dashboard/scripts/security/install-cron.py "$HOME"/repos/chronos/scripts/security-monitor/install-cron.py; do
        [[ -f "$f" ]] || continue
        run "cron: ${f#"$HOME"/repos/}" /usr/bin/python3 "$f" || warn "$f failed"
    done

    if [[ -d /Applications/Docker.app ]]; then
        open -a Docker 2>/dev/null || true
        followup "Restore ~/repos/olympus-dashboard/data from the backup, then: cd ~/repos/olympus-dashboard && docker compose up -d"
    else
        warn "Docker Desktop is not installed (cask docker-desktop)"
    fi
    return 0
}

step_services() {
    if ! ask_yes_no "Start sketchybar?"; then return 2; fi

    if command -v sketchybar &>/dev/null; then
        run "sketchybar" brew services restart sketchybar || warn "sketchybar did not start"
    else
        warn "sketchybar is not installed"
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

# Which Mac this is: --host, else the saved choice, else asked (guess: the hostname).
resolve_host() {
    local guess=sanctum name h
    name=$(scutil --get LocalHostName 2>/dev/null | tr '[:upper:]' '[:lower:]')
    for h in "${HOSTS[@]}"; do [[ "$name" == *"$h"* ]] && guess=$h; done
    if [[ -z "$HOST" && -f "$HOST_FILE" ]]; then guess=$(<"$HOST_FILE"); fi
    while [[ -z "$HOST" ]]; do
        HOST=$(ask_input "Which Mac is this — ${HOSTS[*]}?" "$guess")
        contains "$(IFS=,; echo "${HOSTS[*]}")" "$HOST" || { note "one of: ${HOSTS[*]}"; HOST=""; }
    done
    [[ $HOST == olympus ]] && REPOS_DIR="$HOME/repos"
    mkdir -p "$(dirname "$HOST_FILE")" && printf '%s\n' "$HOST" >"$HOST_FILE"
    log_raw "host profile: $HOST"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)  ASSUME_YES=1 ;;
            --no-mas)  NO_MAS=1 ;;
            --host)    HOST="${2:-}"; shift ;;
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
    [[ -z "$HOST" ]] || contains "$(IFS=,; echo "${HOSTS[*]}")" "$HOST" || fatal "--host must be one of: ${HOSTS[*]}"
    mkdir -p "$(dirname "$LOG")"
    log_raw ""
    log_raw "################ bootstrap $(date '+%F %T') ################"

    resolve_host
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
    if [[ $NO_MAS -eq 1 ]] && grep -qE '^mas ' "$(brewfile)" 2>/dev/null; then
        followup "Sign in to the App Store, then: brew bundle --file $(brewfile) (mas apps were skipped)"
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
