# You can override some default options with config.fish:
#
#  set -g theme_short_path yes
#  set -g theme_stash_indicator yes
#  set -g theme_ignore_ssh_awareness yes

function fish_prompt
  set -l last_command_status $status
  set -l cwd

  if test "$theme_short_path" = 'yes'
    set cwd (basename (prompt_pwd))
  else
    set cwd (prompt_pwd)
  end

  set -l fish     "⋊>"

  set -l primary_color      (set_color normal)
  set -l secondary_color    (set_color cyan)
  set -l tertiary_color     (set_color green)
  set -l error_color        (set_color $fish_color_error 2> /dev/null; or set_color red --bold)
  set -l repository_color   (set_color yellow)
  set -l special_color      (set_color magenta)

  set -l prompt_string (whoami)"$tertiary_color@$special_color"(hostname -s)

  if test "$theme_ignore_ssh_awareness" != 'yes' -a -n "$SSH_CLIENT$SSH_TTY"
    # may be used in future
    set prompt_string (whoami)"@"(hostname -s)
  end

  if test $last_command_status -eq 0
    echo -ns $secondary_color $prompt_string $primary_color
  else
    echo -ns $error_color $prompt_string $primary_color
  end
  echo -ns " " $primary_color \[ $tertiary_color $cwd $primary_color \]

  echo -nse $secondary_color "\n$fish "
end
