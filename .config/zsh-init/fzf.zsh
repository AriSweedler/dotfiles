eval "$(fzf --zsh)"

# fzf config
#
# Use 'rg' for 'fzf' - if possible
if type rg &> /dev/null; then
  export FZF_DEFAULT_COMMAND='rg --files --hidden'
  function _fzf_compgen_path() {
    rg --files --hidden
  }
fi

function cfg_fzf_def_opts() {
  # Define the "modes"
  ## Show hidden AND .gitignored files
  local CTRL_A="reload:'rg --files --hidden --no-ignore'"
  ## Show just files
  local CTRL_X="reload:'rg --files'"

  local fzf_default_opts_arr=(
    # Use exact match by default. Now `'` toggles back to fuzzy match
    --exact

    # 2 modes
    --bind="ctrl-a:${CTRL_A}"
    --bind="ctrl-x:${CTRL_X}"
  )
  export FZF_DEFAULT_OPTS="${fzf_default_opts_arr[*]}"
}
cfg_fzf_def_opts
unset -f cfg_fzf_def_opts
