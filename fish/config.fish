source /Users/pseudobun/.config/fish/pseudobun.fish
export PATH="$HOME/.fuelup/bin:$PATH"

export NARGO_HOME="/Users/pseudobun/.nargo"

export PATH="$PATH:$NARGO_HOME/bin"
set -gx PATH /Users/pseudobun/.bb $PATH
uv generate-shell-completion fish | source
uvx --generate-shell-completion fish | source

fish_add_path -a /Users/pseudobun/.foundry/bin

# pnpm
set -gx PNPM_HOME "/Users/pseudobun/Library/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end
