# Run a command DIRECTLY from a keystroke:
# https://unix.stackexchange.com/a/668986/248906
function keystroke-fxn-binding::cc { cc; zle redisplay; }
zle -N keystroke-fxn-binding::cc
bindkey '^o' keystroke-fxn-binding::cc
