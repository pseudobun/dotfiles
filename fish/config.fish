source $HOME/.config/fish/pseudobun.fish
# claude, uv tools and other user-local CLIs
fish_add_path -g $HOME/.local/bin
export PATH="$HOME/.fuelup/bin:$PATH"

set -gx PATH $HOME/.bb $PATH
command -q uv; and uv generate-shell-completion fish | source
command -q uvx; and uvx --generate-shell-completion fish | source

fish_add_path -a $HOME/.foundry/bin

# pnpm
set -gx PNPM_HOME "$HOME/Library/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end
