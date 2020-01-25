#!/bin/bash

# Bash colored output works by sending an unprinted escape sequence to get the
# console to switch "pen color". These characters that don't count for prompt
# script length, but only change the style have to be enclosed in \[ and \] so
# bash knows how to count length

reset="\[\e[0m\]"
black="\[\e[1;30m\]"
red="\[\e[1;31m\]"
green="\[\e[2;32m\]"
yellow="\[\e[1;33m\]"
italic_reverse_black="\[\e[0;3;7;30m\]"
blue="\[\e[0;34m\]"
purple="\[\e[1;35m\]"
reverse_purple="\[\e[7;35m\]"
dark_purple="\[\e[2;35m\]"
cyan="\[\e[0;36m\]"
white="\[\e[1;37m\]"

display_branch() {
  # Return nothing if we're not in a git repo
  if [ ! $(git rev-parse --is-inside-work-tree 2>/dev/null) ]; then
    return
  fi

  # otherwise, return the branch we're on. Can use any one of these
  # git rev-parse --abbrev-ref HEAD
  # git symbolic-ref --short HEAD (fails for detatched head)
  # git name-rev --name-only HEAD (fails for repo w/ no commits)
    # Also, the name git picks for a revision doesn't have to be related to the branch you're currently on.
    # This is intended behavior, of course: https://github.com/git/git/blob/1d89318c48d233d52f1db230cf622935ac3c69fa/builtin/name-rev.c#L42

  # Get the name regularly.
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ $? == "128" ]; then
    echo "in empty repo"
    return
  elif [ "$BRANCH" == "HEAD" ]; then
    # in HEAD is not attatched to any branch, it is direct on a commit
    BRANCH="detatched: $(git name-rev --name-only HEAD)"
  fi
  echo "on ${1}${BRANCH}"

}

################################
# Set the colors and parts of the prompt.

PS1=''

#PS1+="\[\033]0" # Start terminal title and prompt.
#PS1+="\w \$(display_branch)"
#PS1+="\007\]\n" # end terminal title and prompt.

# Highlight the user name when logged in as root.
if [ $EUID == 0 ]; then
  userStyle="${reverse_purple}"
  prompt="${purple}#"
else
  userStyle="${blue}"
  prompt="${dark_purple}$"
fi

PREAMBLE="${italic_reverse_black} [\@] " # time #preamble is for spacing before each line
PS1+="${PREAMBLE}"
PS1+="${reset} "
PS1+="${userStyle}\u" # username
PS1+="${reset} in "
PS1+="${green}\W" # working directory full path
PS1+="${reset} "
PS1+="\$(display_branch '${cyan}') " # Git repository details
PS1+="${reset}\n"
PS1+="${PREAMBLE}${reset} " # newline, prompt, and reset color
PS1+="🚀 ${prompt} "
PS1+="${reset}"
export PS1

PS2="${yellow}→ ${reset}"
export PS2
