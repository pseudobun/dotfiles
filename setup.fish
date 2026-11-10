# Run by bootstrap.sh (step "fish"). Safe to re-run.

if functions -q omf
    echo "Setting up omf..."
    omf install bass
    omf theme pseudobun
    echo "Finished omf setup."
end

fish_add_path /opt/homebrew/opt/postgresql@15/bin
fish_add_path ~/.cargo/bin

if not functions -q fisher
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
    and fisher install jorgebucaran/fisher
end
