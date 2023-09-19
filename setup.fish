echo "Setting up omf..."
omf install bass
omf install nvm
omf theme pseudobun
echo "Finished omf setup."
echo "Setting up pyenv..."
set -Ux PYENV_ROOT $HOME/.pyenv
fish_add_path $PYENV_ROOT/bin
echo "Finished pyenv setup."