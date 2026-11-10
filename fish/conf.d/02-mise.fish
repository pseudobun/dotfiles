# mise: per-directory and global tool versions (Java). Config: ~/.config/mise/config.toml
if status is-interactive; and command -q mise
    mise activate fish | source
else if command -q mise
    # non-interactive shells (agents, scripts) still get the global tools on PATH
    mise activate fish --shims | source
end
