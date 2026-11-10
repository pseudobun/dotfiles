# sdkman-cli comes from Homebrew (sdkman/tap); point sdkman-for-fish (conf.d/sdk.fish) at it
# before that plugin loads, or it looks for ~/.sdkman and warns on every shell.
if not set -q SDKMAN_DIR; and test -d /opt/homebrew/opt/sdkman-cli/libexec
    set -gx SDKMAN_DIR /opt/homebrew/opt/sdkman-cli/libexec
end
