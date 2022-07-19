setlocal tabstop=2 expandtab
setlocal foldlevel=0
setlocal autoindent

" {{{ Have bash syntax fold stuff nicely.
"
" Because they don't want that by default. Lmfao... some old dudes wrote this
" and they didn't wanna use 3 variables. So they use a friggin bitfield. In a
" SCRIPTING language. Insane xD
let g:sh_fold_enabled = 1 + 2 + 4

" On unknown `*.sh` files, assume it's bash.
let g:is_bash = 1
" }}}

" Use shellcheck to lint easily
compiler shellcheck

nnoremap <buffer> <Leader>#? :map <Leader>#<CR>
" {{{ Snippets
" {{{ Hashbang with arg parsing loop
let snip_argparsing =<< END
# Parse args
while (( $# > 0 )); do
  case "$1" in
    --arg) arg=true; shift 1 ;;
    --key) value="$2"; shift 2 ;;
    *) echo "Unkonwn argument in ${FUNCNAME[0]}: '$1'"; exit 1 ;;
  esac
done
END
nnoremap <buffer> <Leader>#a o<Esc>:let @h=snip_argparsing->join("\n")<CR>"hp
" }}}
" {{{ Table driven programming
let snip_table =<< END
readonly my_table=(
  "line1col1, line1col2, line1col3"
  "2col1,     col2.2,    lastcol_3"
  "111111111, 222222222, 333333333"
)
for line in "${my_table[@]}"
do
    IFS=' ,' read col1 col2 col3 <<< "$line"
    echo "From line='$line' we see column1='$col1' column2='$col2' column3='$col3'"
done
END
nnoremap <buffer> <Leader>#t o<Esc>:let @h=snip_table->join("\n")<CR>"hp
" }}}
" {{{ Read in the output of a command (one line == 1 entry in the array)
let snip_readlines =<< END
read -ar lines < <(git diff --cached --name-only)
for line in "${lines[@]}"; do
  echo "Hello line '$line'"
done
END
nnoremap <buffer> <Leader>#r o<Esc>:let @h=snip_readlines->join("\n")<CR>"hp
" }}}
" }}}
"
" Abbrevs
iabbrev loggy echo "Function='${FUNCNAME[0]}' with '$#' args: '$*'"
