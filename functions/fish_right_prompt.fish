function fish_right_prompt
  if test $CMD_DURATION
    set duration (echo "$CMD_DURATION 1000" | awk '{printf "%.3fs", $1 / $2}')
    echo $duration
  end

  # set_color $fish_color_autosuggestion 2> /dev/null; or set_color 555
  # date "+%H:%M:%S"
  # set_color normal

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
  if git_is_repo
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
  end
end
