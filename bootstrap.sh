#!/bin/bash

# ============================================================================
# pseudobun's dotfiles - Interactive Bootstrap Install Wizard
# ============================================================================
#
# Usage:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/pseudobun/dotfiles/main/bootstrap.sh)"
#
# Or locally:
#   ./bootstrap.sh
#
# ============================================================================

set -uo pipefail

# --- Global State ---
dotfiles_path=~/.dotfiles

# --- Colors & Formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Helper Functions ---

info()    { echo -e "  ${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "  ${GREEN}[ OK ]${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC}  $1"; }
err()     { echo -e "  ${RED}[ ERR]${NC}  $1"; }

fatal() {
    echo ""
    echo -e "  ${RED}[FATAL]${NC} $1"
    echo -e "  ${RED}Aborting installation.${NC}"
    exit 1
}

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}pseudobun's dotfiles - Install Wizard${NC}                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}──────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}$1${NC}"
    echo -e "${BLUE}──────────────────────────────────────────────────────────${NC}"
    echo ""
}

# Ask yes/no. Returns 0 for yes, 1 for no.
# Usage: ask_yes_no "Question?" [default: y|n]
ask_yes_no() {
    local question="$1"
    local default="${2:-y}"
    local hint

    if [[ "$default" == "y" ]]; then
        hint="[Y/n]"
    else
        hint="[y/N]"
    fi

    while true; do
        echo -en "  ${BOLD}${question} ${hint}: ${NC}"
        read -r answer
        answer="${answer:-$default}"
        case "$answer" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo])     return 1 ;;
            *) echo "  Please answer y or n." ;;
        esac
    done
}

# Prompt user for input with a default value.
# Usage: ask_input "Prompt" "default_value"  -> prints to stdout
ask_input() {
    local question="$1"
    local default="$2"
    echo -en "  ${BOLD}${question} (default: ${default}): ${NC}" >&2
    read -r answer
    echo "${answer:-$default}"
}

# Wait for user to complete manual steps. Returns 0 if done, 1 if skipped.
wait_for_manual_step() {
    echo ""
    echo -en "  ${YELLOW}Press Enter when done, or 's' to skip: ${NC}"
    read -r answer
    if [[ "$answer" == "s" || "$answer" == "S" ]]; then
        warn "Manual step skipped."
        return 1
    fi
    return 0
}

# ============================================================================
# Step 1: Xcode Command Line Tools (REQUIRED)
# ============================================================================
step_xcode_tools() {
    print_section "Step 1/17: Xcode Command Line Tools (REQUIRED)"

    if command -v xcode-select &>/dev/null && xcode-select -p &>/dev/null; then
        success "Xcode CLI tools are already installed."
        info "Run 'xcode-select --install' to update if needed."
        return 0
    fi

    info "Xcode CLI tools are required for compilers, git, and other build tools."
    echo ""

    if ! ask_yes_no "Install Xcode CLI tools?"; then
        fatal "Xcode CLI tools are required. Cannot continue without them."
    fi

    xcode-select --install 2>/dev/null || true

    info "Waiting for Xcode CLI installation to complete..."
    info "A system dialog should appear. Follow the prompts."

    until xcode-select -p &>/dev/null; do
        sleep 5
    done

    success "Xcode CLI tools installed."
}

# ============================================================================
# Step 2: Clone Dotfiles Repository (REQUIRED)
# ============================================================================
step_clone_dotfiles() {
    print_section "Step 2/17: Clone Dotfiles Repository (REQUIRED)"

    dotfiles_path=$(ask_input "Path to clone dotfiles" "$dotfiles_path")

    if [[ -d "$dotfiles_path" ]]; then
        warn "Directory '$dotfiles_path' already exists."

        if ask_yes_no "Use existing directory?"; then
            cd "$dotfiles_path" || fatal "Cannot enter directory '$dotfiles_path'."
            success "Using existing dotfiles at: $(pwd)"
            return 0
        fi

        if ask_yes_no "Remove and re-clone?" "n"; then
            rm -rf "$dotfiles_path"
        else
            fatal "Cannot continue without a dotfiles directory."
        fi
    fi

    info "Cloning https://github.com/pseudobun/dotfiles.git ..."
    if ! git clone https://github.com/pseudobun/dotfiles.git "$dotfiles_path"; then
        fatal "Failed to clone dotfiles repository."
    fi

    cd "$dotfiles_path" || fatal "Cannot enter directory '$dotfiles_path'."
    success "Dotfiles cloned to: $(pwd)"
}

# ============================================================================
# Step 3: Homebrew & Packages
# ============================================================================
step_homebrew() {
    print_section "Step 3/17: Homebrew & Packages"

    info "This step will:"
    echo "    1. Install or update Homebrew"
    echo "    2. Install all packages from Brewfile"
    echo "       (formulae, casks, App Store apps, VS Code extensions)"
    echo ""
    warn "This may take a long time depending on the number of packages."
    echo ""

    if ! ask_yes_no "Proceed with Homebrew setup?"; then
        warn "Skipped Homebrew. Many later steps depend on packages from the Brewfile."
        return 0
    fi

    if ! command -v brew &>/dev/null; then
        info "Installing Homebrew..."
        if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
            fatal "Homebrew installation failed."
        fi

        # Add Homebrew to PATH for the current session
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
        success "Homebrew installed."
    else
        info "Homebrew already installed. Updating..."
        brew update && brew upgrade || warn "Homebrew update encountered issues."
        success "Homebrew updated."
    fi

    info "Installing packages from Brewfile (this may take a while)..."
    if ! brew bundle --file "$dotfiles_path/Brewfile"; then
        warn "Some Brewfile packages failed. Review the output above."
    else
        success "All Brewfile packages installed."
    fi
}

# ============================================================================
# Step 4: Shell Setup (Fish, Oh-My-Fish, Fisher)
# ============================================================================
step_shell_setup() {
    print_section "Step 4/17: Shell Setup"

    info "This step will:"
    echo "    1. Set Fish as your default shell"
    echo "    2. (Optional) Install Oh-My-Fish — experimental"
    echo "    3. Install Fisher plugin manager"
    echo "    4. Install Fisher plugins (pnpm-shell-completion)"
    echo ""

    if ! ask_yes_no "Set up Fish shell environment?"; then
        warn "Skipped shell setup."
        return 0
    fi

    # --- Fish as default shell ---
    local fish_path
    fish_path="$(which fish 2>/dev/null)" || true

    if [[ -z "$fish_path" ]]; then
        warn "Fish shell not found. Did the Homebrew step complete?"
        warn "Skipping shell setup."
        return 0
    fi

    if [[ "$SHELL" == "$fish_path" ]]; then
        success "Fish is already the default shell."
    elif ask_yes_no "Set Fish as your default shell?"; then
        if ! grep -qF "$fish_path" /etc/shells 2>/dev/null; then
            echo "$fish_path" | sudo tee -a /etc/shells >/dev/null || fatal "Failed to add Fish to /etc/shells (needs sudo)."
        fi
        if ! chsh -s "$fish_path"; then
            err "Failed to change default shell. You can do it manually: chsh -s $fish_path"
        else
            success "Fish set as default shell."
        fi
    fi

    # --- Oh-My-Fish ---
    if ask_yes_no "Install Oh-My-Fish? (EXPERIMENTAL)" "n"; then
        info "Installing Oh-My-Fish..."
        if curl -sL https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install | fish; then
            success "Oh-My-Fish installed."
        else
            warn "Oh-My-Fish installation had issues."
        fi
    fi

    # --- Fisher ---
    if ask_yes_no "Install Fisher plugin manager?"; then
        info "Installing Fisher..."
        if fish -c 'curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher'; then
            success "Fisher installed."
        else
            warn "Fisher installation had issues."
        fi

        if ask_yes_no "Install Fisher plugins (pnpm-shell-completion)?"; then
            if fish -c 'fisher install g-plane/pnpm-shell-completion'; then
                success "Fisher plugins installed."
            else
                warn "Fisher plugin installation had issues."
            fi
        fi
    fi
}

# ============================================================================
# Step 5: GPG Setup
# ============================================================================
step_gpg_setup() {
    print_section "Step 5/17: GPG Setup"

    info "This step will:"
    echo "    1. Configure GPG agent with pinentry-mac"
    echo "    2. Set GPG defaults (use-agent, no-emit-version)"
    echo "    3. Optionally import existing GPG keys from file"
    echo "    4. Optionally generate a new GPG key pair"
    echo "    5. Set a default signing key for git"
    echo ""

    if ! ask_yes_no "Set up GPG?"; then
        warn "Skipped GPG setup."
        return 0
    fi

    # --- GPG directories ---
    if [[ ! -d ~/.gnupg ]]; then
        mkdir -p ~/.gnupg && chmod 700 ~/.gnupg
        info "Created ~/.gnupg directory."
    fi

    local gpg_agent_conf=~/.gnupg/gpg-agent.conf
    local gpg_conf=~/.gnupg/gpg.conf
    touch "$gpg_agent_conf" "$gpg_conf"

    # --- pinentry-mac ---
    if command -v brew &>/dev/null; then
        local pinentry_path
        pinentry_path="$(brew --prefix)/bin/pinentry-mac"
        if [[ -f "$pinentry_path" ]]; then
            if ! grep -qF "pinentry-program" "$gpg_agent_conf" 2>/dev/null; then
                echo "pinentry-program $pinentry_path" >> "$gpg_agent_conf"
                success "Configured pinentry-mac."
            else
                info "pinentry-program already configured."
            fi
        else
            warn "pinentry-mac not found at $pinentry_path. Skipping."
        fi
    fi

    # --- GPG defaults ---
    grep -qF "use-agent" "$gpg_conf" 2>/dev/null       || echo "use-agent" >> "$gpg_conf"
    grep -qF "no-emit-version" "$gpg_conf" 2>/dev/null || echo "no-emit-version" >> "$gpg_conf"
    success "GPG base configuration written."

    # --- Key management ---
    echo ""
    info "GPG key options:"
    echo "    a) Import existing keys from file"
    echo "    b) Generate a new key pair"
    echo "    c) Skip — use pre-configured default key"
    echo ""

    if ask_yes_no "Import existing GPG keys from file?" "n"; then
        echo -en "  ${BOLD}Path to public key file (Enter to skip): ${NC}"
        read -r pub_key_path
        if [[ -n "$pub_key_path" ]]; then
            if [[ ! -f "$pub_key_path" ]]; then
                err "File not found: $pub_key_path"
            elif gpg --import "$pub_key_path" 2>/dev/null; then
                success "Public key imported."
            else
                warn "Failed to import public key."
            fi
        fi

        echo -en "  ${BOLD}Path to private key file (Enter to skip): ${NC}"
        read -r priv_key_path
        if [[ -n "$priv_key_path" ]]; then
            if [[ ! -f "$priv_key_path" ]]; then
                err "File not found: $priv_key_path"
            elif gpg --import "$priv_key_path" 2>/dev/null; then
                success "Private key imported."
            else
                warn "Failed to import private key."
            fi
        fi

        # Pick default key
        if ask_yes_no "Set a default GPG signing key for git?"; then
            echo ""
            info "Available secret keys:"
            gpg --list-secret-keys --keyid-format=long 2>/dev/null || true
            echo ""
            echo -en "  ${BOLD}Enter key ID to use as default (Enter to skip): ${NC}"
            read -r key_id
            if [[ -n "$key_id" ]]; then
                # Replace or add default-key line
                if grep -qF "default-key" "$gpg_conf" 2>/dev/null; then
                    sed -i.bak "s/^default-key.*/default-key $key_id/" "$gpg_conf" && rm -f "$gpg_conf.bak"
                else
                    echo "default-key $key_id" >> "$gpg_conf"
                fi
                success "Default GPG key set to $key_id."
            fi
        fi

    elif ask_yes_no "Generate a new GPG key pair?" "n"; then
        info "Launching GPG key generation wizard..."
        if gpg --full-generate-key; then
            success "GPG key generated."
            echo ""
            info "Your secret keys:"
            gpg --list-secret-keys --keyid-format=long 2>/dev/null || true
            echo ""

            if ask_yes_no "Set the new key as default for git signing?"; then
                echo -en "  ${BOLD}Enter the key ID from above: ${NC}"
                read -r key_id
                if [[ -n "$key_id" ]]; then
                    if grep -qF "default-key" "$gpg_conf" 2>/dev/null; then
                        sed -i.bak "s/^default-key.*/default-key $key_id/" "$gpg_conf" && rm -f "$gpg_conf.bak"
                    else
                        echo "default-key $key_id" >> "$gpg_conf"
                    fi
                    success "Default GPG key set to $key_id."
                fi
            fi
        else
            warn "GPG key generation failed or was cancelled."
        fi
    else
        # Fall back to the pre-configured key
        if ! grep -qF "default-key" "$gpg_conf" 2>/dev/null; then
            echo "default-key 7A5C62926461D990A0575C9EA03490EFF21E32E9" >> "$gpg_conf"
        fi
        info "Using pre-configured default GPG key."
    fi

    success "GPG setup complete."
}

# ============================================================================
# Step 6: SSH Key Setup
# ============================================================================
step_ssh_setup() {
    print_section "Step 6/17: SSH Key Setup"

    info "This step will:"
    echo "    1. Generate a new SSH key pair OR import existing keys"
    echo "    2. Add the key to the SSH agent"
    echo "    3. Configure macOS Keychain integration"
    echo "    4. Display the public key for adding to GitHub, etc."
    echo ""

    if ! ask_yes_no "Set up SSH keys?" "n"; then
        warn "Skipped SSH setup."
        return 0
    fi

    local ssh_key_path=""

    if ask_yes_no "Generate a new SSH key pair?"; then
        echo -en "  ${BOLD}Email address for the key: ${NC}"
        read -r ssh_email
        if [[ -z "$ssh_email" ]]; then
            warn "No email provided. Skipping SSH key generation."
            return 0
        fi

        ssh_key_path=$(ask_input "Key file path" "$HOME/.ssh/id_ed25519")

        if [[ -f "$ssh_key_path" ]]; then
            warn "Key already exists at $ssh_key_path."
            if ! ask_yes_no "Overwrite?" "n"; then
                info "Keeping existing key."
                # Still set path so we can add to agent
            else
                mkdir -p "$(dirname "$ssh_key_path")"
                if ! ssh-keygen -t ed25519 -C "$ssh_email" -f "$ssh_key_path"; then
                    err "SSH key generation failed."
                    return 0
                fi
                success "SSH key generated at $ssh_key_path."
            fi
        else
            mkdir -p "$(dirname "$ssh_key_path")"
            if ! ssh-keygen -t ed25519 -C "$ssh_email" -f "$ssh_key_path"; then
                err "SSH key generation failed."
                return 0
            fi
            success "SSH key generated at $ssh_key_path."
        fi

    elif ask_yes_no "Import existing SSH keys from file?" "n"; then
        echo -en "  ${BOLD}Path to private key: ${NC}"
        read -r import_priv
        echo -en "  ${BOLD}Path to public key: ${NC}"
        read -r import_pub

        if [[ ! -f "$import_priv" ]]; then
            err "Private key not found: $import_priv"
            return 0
        fi
        if [[ ! -f "$import_pub" ]]; then
            err "Public key not found: $import_pub"
            return 0
        fi

        mkdir -p ~/.ssh
        cp "$import_priv" ~/.ssh/ && chmod 600 ~/.ssh/"$(basename "$import_priv")"
        cp "$import_pub" ~/.ssh/  && chmod 644 ~/.ssh/"$(basename "$import_pub")"
        ssh_key_path=~/.ssh/"$(basename "$import_priv")"
        success "SSH keys imported to ~/.ssh/."
    else
        warn "Skipped SSH key setup."
        return 0
    fi

    # --- Add to agent ---
    if [[ -n "$ssh_key_path" && -f "$ssh_key_path" ]]; then
        info "Starting SSH agent and adding key..."
        eval "$(ssh-agent -s)" >/dev/null 2>&1

        # macOS Keychain integration
        if [[ "$(uname)" == "Darwin" ]]; then
            local ssh_config=~/.ssh/config
            mkdir -p ~/.ssh
            if [[ ! -f "$ssh_config" ]] || ! grep -qF "AddKeysToAgent" "$ssh_config" 2>/dev/null; then
                cat >> "$ssh_config" <<SSHEOF
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile $ssh_key_path
SSHEOF
                info "Configured macOS Keychain integration in ~/.ssh/config."
            fi
        fi

        ssh-add "$ssh_key_path" 2>/dev/null && success "Key added to SSH agent." || warn "Could not add key to agent."
    fi

    # --- Display public key ---
    local pub_key_path="${ssh_key_path}.pub"
    if [[ -f "$pub_key_path" ]]; then
        echo ""
        info "Your public SSH key (add to GitHub at https://github.com/settings/keys):"
        echo ""
        echo -e "  ${DIM}$(cat "$pub_key_path")${NC}"
        echo ""
    fi
}

# ============================================================================
# Step 7: Symlink Dotfiles
# ============================================================================
step_symlink_dotfiles() {
    print_section "Step 7/17: Symlink Dotfiles"

    info "This step will create symlinks for:"
    echo "    - .gitconfig           -> ~/.gitconfig"
    echo "    - Fish functions       -> ~/.config/fish/functions/"
    echo "    - starship.toml        -> ~/.config/"
    echo "    - alacritty.toml       -> ~/.config/alacritty/"
    echo "    - Sketchybar config    -> ~/.config/sketchybar/"
    echo "    - Borders config       -> ~/.config/borders/"
    echo "    - Yabai & skhd config  -> ~/  "
    echo "    - Hammerspoon config   -> ~/.hammerspoon/"
    echo "    - pseudobun.fish       -> ~/.config/fish/"
    echo "    + Download Sketchybar app font"
    echo ""

    if ! ask_yes_no "Create dotfile symlinks?"; then
        warn "Skipped symlinks."
        return 0
    fi

    info "Creating symlinks..."

    # .gitconfig
    ln -fs "$dotfiles_path/.gitconfig" ~/.gitconfig \
        && success ".gitconfig linked" \
        || warn ".gitconfig symlink failed"

    # Fish functions
    mkdir -p ~/.config/fish/functions
    ln -fs "$dotfiles_path"/functions/* ~/.config/fish/functions/ \
        && success "Fish functions linked" \
        || warn "Fish functions symlink failed"

    # Starship
    mkdir -p ~/.config
    ln -fs "$dotfiles_path/starship.toml" ~/.config/ \
        && success "starship.toml linked" \
        || warn "starship.toml symlink failed"

    # Alacritty
    mkdir -p ~/.config/alacritty
    ln -fs "$dotfiles_path/alacritty/alacritty.toml" ~/.config/alacritty/alacritty.toml \
        && success "alacritty.toml linked" \
        || warn "alacritty.toml symlink failed"

    # Sketchybar
    mkdir -p ~/.config/sketchybar/{plugins,items,helper}
    ln -fs "$dotfiles_path/sketchybar/sketchybarrc"  ~/.config/sketchybar/sketchybarrc
    ln -fs "$dotfiles_path/sketchybar/colors.sh"      ~/.config/sketchybar/colors.sh
    ln -fs "$dotfiles_path/sketchybar/icons.sh"        ~/.config/sketchybar/icons.sh
    ln -fs "$dotfiles_path"/sketchybar/helper/*        ~/.config/sketchybar/helper/
    ln -fs "$dotfiles_path"/sketchybar/plugins/*       ~/.config/sketchybar/plugins/
    ln -fs "$dotfiles_path"/sketchybar/items/*         ~/.config/sketchybar/items/
    success "Sketchybar config linked"

    # Borders
    mkdir -p ~/.config/borders
    ln -fs "$dotfiles_path/borders/bordersrc" ~/.config/borders/bordersrc \
        && success "bordersrc linked" \
        || warn "bordersrc symlink failed"

    # Hammerspoon
    mkdir -p ~/.hammerspoon
    ln -fs "$dotfiles_path"/.hammerspoon/* ~/.hammerspoon/ \
        && success "Hammerspoon config linked" \
        || warn "Hammerspoon symlink failed"

    # Fish config
    mkdir -p ~/.config/fish
    ln -fs "$dotfiles_path/pseudobun.fish" ~/.config/fish/ \
        && success "pseudobun.fish linked" \
        || warn "pseudobun.fish symlink failed"

    # Yabai & skhd
    ln -fs "$dotfiles_path/yabai/.yabairc" ~/.yabairc \
        && success ".yabairc linked" \
        || warn ".yabairc symlink failed"
    ln -fs "$dotfiles_path/yabai/.skhdrc" ~/.skhdrc \
        && success ".skhdrc linked" \
        || warn ".skhdrc symlink failed"

    # Sketchybar app font (macOS only)
    if [[ "$(uname)" == "Darwin" ]]; then
        info "Downloading Sketchybar app font..."
        mkdir -p "$HOME/Library/Fonts"
        if curl -sL https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v1.0.16/sketchybar-app-font.ttf \
            -o "$HOME/Library/Fonts/sketchybar-app-font.ttf"; then
            success "Sketchybar app font installed."
        else
            warn "Font download failed."
        fi
    fi

    echo ""
    success "Dotfile symlinks created."
}

# ============================================================================
# Step 8: Fish Shell Configuration (setup.fish)
# ============================================================================
step_fish_config() {
    print_section "Step 8/17: Fish Shell Configuration"

    info "This step runs setup.fish to configure:"
    echo "    - OMF theme (pseudobun)"
    echo "    - PATH additions (PostgreSQL, Cargo)"
    echo "    - Fisher bootstrap"
    echo ""

    if ! ask_yes_no "Run Fish shell configuration (setup.fish)?"; then
        warn "Skipped Fish configuration."
        return 0
    fi

    if ! command -v fish &>/dev/null; then
        warn "Fish shell not found. Skipping."
        return 0
    fi

    if fish "$dotfiles_path/setup.fish"; then
        success "Fish configuration complete."
    else
        warn "Fish setup encountered issues."
    fi
}

# ============================================================================
# Step 9: Development Tools
# ============================================================================
step_dev_tools() {
    print_section "Step 9/17: Development Tools"

    info "Choose which tools to install:"
    echo "    a) Rust         — systems programming (via rustup)"
    echo "    b) Foundry      — Ethereum / Solidity development"
    echo "    c) Bun          — fast JavaScript runtime & bundler"
    echo "    d) Deno         — secure JavaScript / TypeScript runtime"
    echo "    e) Go           — requires manual download (guided)"
    echo "    f) asdf         — multi-language version manager"
    echo ""

    if ! ask_yes_no "Install any development tools?"; then
        warn "Skipped development tools."
        return 0
    fi

    # --- Rust ---
    if ask_yes_no "Install Rust (via rustup)?"; then
        info "Installing Rust..."
        if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh; then
            [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
            if command -v rustc &>/dev/null; then
                success "Rust installed: $(rustc --version)."
            else
                info "Rust installed. Restart your shell to use it."
            fi
        else
            warn "Rust installation had issues."
        fi
    fi

    # --- Foundry ---
    if ask_yes_no "Install Foundry (Ethereum development)?" "n"; then
        info "Installing Foundry..."
        if curl -L https://foundry.paradigm.xyz | bash; then
            success "Foundry bootstrap complete. Run 'foundryup' to finish setup."
        else
            warn "Foundry installation had issues."
        fi
    fi

    # --- Bun ---
    if ask_yes_no "Install Bun (JavaScript runtime)?"; then
        info "Installing Bun..."
        if curl -fsSL https://bun.sh/install | bash; then
            success "Bun installed."
        else
            warn "Bun installation had issues."
        fi
    fi

    # --- Deno ---
    if ask_yes_no "Install Deno (JavaScript runtime)?" "n"; then
        info "Installing Deno..."
        if curl -fsSL https://deno.land/install.sh | sh; then
            success "Deno installed."
        else
            warn "Deno installation had issues."
        fi
    fi

    # --- Go (manual) ---
    if ask_yes_no "Install Go? (manual download required)" "n"; then
        echo ""
        info "Go must be installed manually:"
        echo "    1. Visit https://go.dev/dl/"
        echo "    2. Download the macOS installer (.pkg) for your architecture"
        echo "    3. Run the .pkg installer"
        echo "    4. Verify with: go version"
        echo ""

        if wait_for_manual_step; then
            if command -v go &>/dev/null; then
                success "Go verified: $(go version)."
            else
                warn "Go not found in PATH. You may need to restart your shell."
            fi
        fi
    fi

    # --- asdf ---
    if ask_yes_no "Install asdf (version manager)?" "n"; then
        info "Installing asdf..."
        if git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0; then
            mkdir -p ~/.config/fish/completions
            ln -s ~/.asdf/completions/asdf.fish ~/.config/fish/completions 2>/dev/null || true
            success "asdf installed."
        else
            warn "asdf installation failed."
        fi
    fi
}

# ============================================================================
# Step 10: Spicetify (Spotify Customization)
# ============================================================================
step_spicetify() {
    print_section "Step 10/17: Spicetify (Spotify Customization)"

    info "This step will:"
    echo "    1. Install Spicetify CLI"
    echo "    2. Install Spicetify Marketplace plugin"
    echo ""

    if ! ask_yes_no "Install Spicetify?" "n"; then
        warn "Skipped Spicetify."
        return 0
    fi

    info "Installing Spicetify CLI..."
    if curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh; then
        success "Spicetify CLI installed."
    else
        warn "Spicetify CLI installation failed."
    fi

    info "Installing Spicetify Marketplace..."
    if curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh; then
        success "Spicetify Marketplace installed."
    else
        warn "Spicetify Marketplace installation failed."
    fi
}

# ============================================================================
# Step 11: macOS Defaults
# ============================================================================
step_macos_defaults() {
    print_section "Step 11/17: macOS Defaults"

    info "This step will apply the following preferences:"
    echo "    1. Disable mouse acceleration (com.apple.mouse.scaling = -1)"
    echo "    2. Set dock auto-hide delay to 50ms"
    echo "    3. Enable scroll-to-open on Dock icons"
    echo ""

    if ! ask_yes_no "Apply macOS defaults?"; then
        warn "Skipped macOS defaults."
        return 0
    fi

    defaults write .GlobalPreferences com.apple.mouse.scaling -1 \
        && success "Mouse acceleration disabled." \
        || warn "Failed to set mouse scaling."

    defaults write com.apple.dock autohide-time-modifier -float 0.05 \
        && success "Dock auto-hide delay set to 50ms." \
        || warn "Failed to set dock auto-hide."

    defaults write com.apple.dock "scroll-to-open" -bool "true" \
        && success "Scroll-to-open enabled on Dock." \
        || warn "Failed to enable scroll-to-open."

    info "Some changes require a logout or restart to take effect."
}

# ============================================================================
# Step 12: Terminal Applications
# ============================================================================
step_terminal_apps() {
    print_section "Step 12/17: Terminal Applications"

    info "Install additional terminal emulators:"
    echo "    - Kitty (GPU-accelerated terminal)"
    echo ""

    if ask_yes_no "Install Kitty terminal emulator?" "n"; then
        info "Installing Kitty..."
        if curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin; then
            success "Kitty installed."
        else
            warn "Kitty installation failed."
        fi
    else
        warn "Skipped terminal app installation."
    fi
}

# ============================================================================
# Step 13: Font Installation
# ============================================================================
step_fonts() {
    print_section "Step 13/17: Font Installation"

    info "Liga SFMono Nerd Font is handled by the Brewfile."
    info "This step installs additional bundled fonts from the repo:"
    echo "    - JetBrains Mono  (fonts/JetBrainsMono/)"
    echo "    - Roboto Mono     (fonts/RobotoMono/)"
    echo ""

    if [[ "$(uname)" != "Darwin" ]]; then
        info "On non-macOS, install fonts manually from the fonts/ directory."
        wait_for_manual_step || true
        return 0
    fi

    if ! ask_yes_no "Install bundled fonts to ~/Library/Fonts/?"; then
        warn "Skipped font installation."
        return 0
    fi

    mkdir -p "$HOME/Library/Fonts"
    local count=0

    while IFS= read -r -d '' font_file; do
        cp "$font_file" "$HOME/Library/Fonts/" && ((count++))
    done < <(find "$dotfiles_path/fonts" -type f \( -name '*.ttf' -o -name '*.otf' \) -print0 2>/dev/null)

    if [[ "$count" -gt 0 ]]; then
        success "$count font files installed to ~/Library/Fonts/."
    else
        warn "No font files (.ttf/.otf) found in fonts/ directory."
    fi
}

# ============================================================================
# Step 14: iTerm2 Configuration (Manual)
# ============================================================================
step_iterm_config() {
    print_section "Step 14/17: iTerm2 Configuration"

    info "iTerm2 settings must be imported through the app UI."
    echo ""

    if ! ask_yes_no "Configure iTerm2?"; then
        warn "Skipped iTerm2 configuration."
        return 0
    fi

    if [[ "$(uname)" != "Darwin" ]]; then
        warn "iTerm2 is macOS-only. Skipping."
        return 0
    fi

    if [[ ! -d "/Applications/iTerm.app" ]]; then
        warn "iTerm2 is not installed. Skipping."
        return 0
    fi

    echo ""
    info "${BOLD}Step A — Import Color Scheme:${NC}"
    echo "    1. Open iTerm2"
    echo "    2. Go to: iTerm > Preferences > Profiles > Colors > Color Presets ..."
    echo "    3. Click 'Import...' and select:"
    echo "       $dotfiles_path/itermcolors/DraculaPlus.itermcolors"
    echo "    4. Choose 'DraculaPlus' from the Color Presets dropdown"
    echo ""
    info "${BOLD}Step B — Import Profile:${NC}"
    echo "    5. Go to: iTerm > Preferences > Profiles"
    echo "    6. Click: Other actions ... > Import JSON profiles ..."
    echo "    7. Select: $dotfiles_path/profiles/pseudobun.json"
    echo ""
    info "${BOLD}Step C — Import Key Bindings:${NC}"
    echo "    8. Go to: iTerm > Preferences > Keys > Key Bindings"
    echo "    9. Click: Presets ... > Import ..."
    echo "   10. Select: $dotfiles_path/profiles/pseudobun.itermkeymap"
    echo ""

    if wait_for_manual_step; then
        if defaults read com.googlecode.iterm2 &>/dev/null 2>&1; then
            success "iTerm2 preferences detected."
        else
            info "Could not verify iTerm2 preferences (this is normal if iTerm2 hasn't been opened yet)."
        fi
    fi
}

# ============================================================================
# Step 15: Raycast Configuration
# ============================================================================
step_raycast_config() {
    print_section "Step 15/17: Raycast Configuration"

    info "Raycast is an alternative to Spotlight."
    info "Configuration file: $dotfiles_path/raycast/raycast.rayconfig"
    echo ""

    if ! ask_yes_no "Import Raycast configuration?"; then
        warn "Skipped Raycast configuration."
        return 0
    fi

    if [[ "$(uname)" == "Darwin" && -d "/Applications/Raycast.app" ]]; then
        info "Opening Raycast config file for import..."
        if open "$dotfiles_path/raycast/raycast.rayconfig" 2>/dev/null; then
            info "Raycast import dialog should appear."
            echo "    Follow the prompts in Raycast to complete the import."
            echo ""
            if wait_for_manual_step; then
                success "Raycast configuration imported."
            fi
        else
            warn "Failed to open Raycast config file."
        fi
    else
        info "Raycast not found. To import manually later:"
        echo "    1. Open Raycast"
        echo "    2. Import the configuration from: $dotfiles_path/raycast/raycast.rayconfig"
        echo ""
        wait_for_manual_step || true
    fi
}

# ============================================================================
# Step 16: GitHub CLI Authentication
# ============================================================================
step_github_auth() {
    print_section "Step 16/17: GitHub CLI Authentication"

    info "This will authenticate the GitHub CLI (gh) for repository access."
    echo ""

    if ! ask_yes_no "Authenticate with GitHub CLI?"; then
        warn "Skipped GitHub authentication."
        return 0
    fi

    if ! command -v gh &>/dev/null; then
        warn "GitHub CLI (gh) not found. Install via Homebrew first."
        return 0
    fi

    if gh auth status &>/dev/null 2>&1; then
        success "GitHub CLI is already authenticated."
        if ! ask_yes_no "Re-authenticate?" "n"; then
            return 0
        fi
    fi

    if gh auth login; then
        if gh auth status &>/dev/null 2>&1; then
            success "GitHub CLI authenticated."
        else
            warn "GitHub CLI authentication could not be verified."
        fi
    else
        warn "GitHub authentication failed or was cancelled."
    fi
}

# ============================================================================
# Step 17: Start Services
# ============================================================================
step_start_services() {
    print_section "Step 17/17: Start Services"

    info "Available services to start:"
    echo "    1. Sketchybar (custom menu bar)"
    echo "    2. Yabai (tiling window manager)"
    echo "    3. skhd (hotkey daemon)"
    echo "    4. Spicetify apply (Spotify customization)"
    echo ""
    warn "Yabai and skhd may require editing .plist files first."
    info "Reference: https://gist.github.com/pseudobun/34c42b0bf20e82f114fd232c8ce55fe2"
    echo ""

    if ! ask_yes_no "Start any services?"; then
        warn "Skipped starting services."
        return 0
    fi

    # --- Sketchybar ---
    if ask_yes_no "Start Sketchybar (menu bar)?"; then
        if brew services start sketchybar 2>/dev/null; then
            success "Sketchybar started."
        else
            warn "Failed to start Sketchybar."
        fi
    fi

    # --- Yabai & skhd ---
    if ask_yes_no "Start Yabai and skhd (window management)?"; then
        echo ""
        warn "Yabai and skhd need .plist files edited to change the shell to /bin/sh."
        info "See: https://gist.github.com/pseudobun/34c42b0bf20e82f114fd232c8ce55fe2"
        echo ""
        echo "    Steps:"
        echo "    1. Find yabai/skhd .plist files (usually in ~/Library/LaunchAgents/)"
        echo "    2. Change the shell path from /bin/bash to /bin/sh"
        echo "    3. See the gist above for exact instructions"
        echo ""

        if ask_yes_no "Proceed with starting yabai/skhd (have you edited .plist or want to proceed anyway)?"; then
            yabai --stop-service 2>/dev/null || true
            if yabai --start-service 2>/dev/null; then
                success "Yabai started."
            else
                warn "Failed to start Yabai."
            fi

            skhd --stop-service 2>/dev/null || true
            if skhd --start-service 2>/dev/null; then
                success "skhd started."
            else
                warn "Failed to start skhd."
            fi
        else
            info "Skipped yabai/skhd. Start manually after editing .plist files."
        fi
    fi

    # --- Spicetify ---
    if command -v spicetify &>/dev/null; then
        if ask_yes_no "Apply Spicetify modifications?" "n"; then
            if spicetify apply 2>/dev/null; then
                success "Spicetify applied."
            else
                warn "Spicetify apply failed. Make sure Spotify has been opened at least once."
            fi
        fi
    fi
}

# ============================================================================
# Finish
# ============================================================================
step_finish() {
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}Setup Complete!${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo ""

    info "Remaining manual steps you may want to do:"
    echo "    - Install Go:           https://go.dev/doc/install"
    echo "    - iTerm2 config:        import colors, profile, keybindings"
    echo "    - Raycast:              import raycast.rayconfig"
    echo "    - Yabai .plist:         edit shell to /bin/sh"
    echo "    - GitHub SSH key:       https://github.com/settings/keys"
    echo ""

    if ask_yes_no "Reboot your Mac now?" "n"; then
        info "Rebooting..."
        sudo reboot
    else
        info "Remember to reboot when convenient for all changes to take effect."
        echo ""
        if command -v fish &>/dev/null; then
            if ask_yes_no "Launch Fish shell now?"; then
                exec fish
            fi
        fi
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    print_header

    info "This wizard will guide you through setting up pseudobun's dotfiles."
    info "Each step can be accepted, skipped, or customized."
    echo ""

    echo -e "  ${BOLD}Steps:${NC}"
    echo "     1. Xcode Command Line Tools  (required)"
    echo "     2. Clone Dotfiles Repository  (required)"
    echo "     3. Homebrew & Packages"
    echo "     4. Shell Setup (Fish, OMF, Fisher)"
    echo "     5. GPG Configuration & Keys"
    echo "     6. SSH Key Setup"
    echo "     7. Symlink Dotfiles"
    echo "     8. Fish Shell Configuration"
    echo "     9. Development Tools (Rust, Foundry, Bun, Deno, Go, asdf)"
    echo "    10. Spicetify (Spotify Customization)"
    echo "    11. macOS Defaults"
    echo "    12. Terminal Applications (Kitty)"
    echo "    13. Font Installation"
    echo "    14. iTerm2 Configuration (manual)"
    echo "    15. Raycast Configuration"
    echo "    16. GitHub CLI Authentication"
    echo "    17. Start Services (Sketchybar, Yabai, skhd)"
    echo ""

    if ! ask_yes_no "Ready to begin?"; then
        info "Run this script again when you're ready."
        exit 0
    fi

    step_xcode_tools
    step_clone_dotfiles
    step_homebrew
    step_shell_setup
    step_gpg_setup
    step_ssh_setup
    step_symlink_dotfiles
    step_fish_config
    step_dev_tools
    step_spicetify
    step_macos_defaults
    step_terminal_apps
    step_fonts
    step_iterm_config
    step_raycast_config
    step_github_auth
    step_start_services
    step_finish
}

main "$@"
