set -g fish_greeting
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH
set --export GPG_TTY $(tty)

eval (/opt/homebrew/bin/brew shellenv)
fish_add_path ~/.cargo/bin/
load_nvm > /dev/stderr

kubectl completion fish | source
alias please='sudo'
alias launchtsm='osascript $HOME/.dotfiles/transmission_lift.osascript'
alias sweep='fd --hidden --no-ignore "^.DS_Store\$" --exclude "*node_modules*" --exec rm'
alias tsm='transmission-remote'
alias watchtsm="watch --interval 1 'transmission-remote -l'"
# pyenv init - | source
zoxide init fish | source
starship init fish | source

# base abbrs
abbr -a htop 'btm'
abbr -a top 'btm'
abbr -a cd 'z'
abbr -a l 'exa -ahliH --icons'
abbr -a k 'kubectl'

# git abbrs
abbr -a ga 'git add'
abbr -a gaa 'git add --all'

abbr -a gs 'git status'

abbr -a gp 'git push'
abbr -a gc 'git checkout'
abbr -a gcm 'git commit'
abbr -a gcma 'git commit -am'
abbr -a gm 'git merge'
abbr -a gr 'git rebase'
abbr -a gl 'git pull'
abbr -a gf 'git fetch'

abbr -a gb 'git branch'
abbr -a gba 'git branch -a'
abbr -a gbr 'git branch -r'
abbr -a gbd 'git branch -d'

abbr -a grp 'git remote prune origin'

function cs
   z $argv
   exa -ahliH --icons
end

function md
   markdown $argv[1] | lynx -stdin
end

function brew
   command brew $argv
   if contains "upgrade" $argv; or contains "update" $argv; or contains "outdated" $argv
     sketchybar --trigger brew_update
   end
 end

# tabtab source for pnpm package
# uninstall by removing these lines
[ -f ~/.config/tabtab/fish/__tabtab.fish ]; and . ~/.config/tabtab/fish/__tabtab.fish; or true