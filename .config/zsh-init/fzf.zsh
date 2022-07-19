source_file "$HOME/.fzf.zsh"

# fzf config
# Use 'rg' for 'fzf' - if possible
if type rg &> /dev/null; then
  export FZF_DEFAULT_COMMAND='rg --files --hidden'
  function _fzf_compgen_path() {
    rg --files --hidden
  }
fi
# Use exact match by default. Now `'` toggles back to fuzzy match
export FZF_DEFAULT_OPTS='--exact'

