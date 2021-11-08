call system("which rg")
if ! v:shell_error
  " Make the grepprg rg. This is pretty much as good at git grep but it's cooler
  let &grepprg="rg --vimgrep --smart-case"
else
  " Make the grepprg git grep. This always searches from the root of the repo
  " and ignores files that .gitignore specifies. It's a lil nicer.
  let &grepprg="git grep --line-number"
endif
