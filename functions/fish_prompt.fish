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
  set -l ahead    "↑"
  set -l behind   "↓"
  set -l diverged "⥄"
  set -l dirty    "✗"
  set -l stash    "="
  set -l none     "✓"

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
    echo -n -s $secondary_color $prompt_string $primary_color
  else
    echo -n -s $error_color $prompt_string $primary_color
  end

  if git_is_repo
    if test "$theme_short_path" = 'yes'
      set root_folder (command git rev-parse --show-toplevel 2> /dev/null)
      set parent_root_folder (dirname $root_folder)
      set cwd (echo $PWD | sed -e "s|$parent_root_folder/||")
    end

    echo -n -s " " $primary_color \[ $tertiary_color $cwd $primary_color \]
    echo -n -s "$special_color  " $repository_color (git_branch_name) $primary_color " "


    set -l list
    if test "$theme_stash_indicator" = yes; and git_is_stashed
      set list $list $stash
    end
    if git_is_touched
      set list $list $dirty
    end
    echo -n $list

    if test -z "$list"
      echo -n -s (git_ahead $ahead $behind $diverged $none)
    end
  else
    echo -n -s " " $primary_color \[ $tertiary_color $cwd $primary_color \]
  end

  echo -n -s $secondary_color " $fish "
end
