" Turn <XYZ>@<ABC> into
"
" Host NEWHOST
"     HOSTNAME ABC
"     USER XYZ
nnoremap <buffer> <Leader>H "adt@x"bd$iHost NEWHOST<CR><Tab>Hostname <C-r>b<CR><Tab>User <C-r>a<ESC>

nnoremap <buffer> <Leader>#? :map <Leader>#<CR>
" {{{ Snippets
" {{{ Now Host
let snip_newhost =<< END

Host SNIP_SHORTNAME
	Hostname SNIP_IPADDR
	User SNIP_USERNAME
END
nnoremap <buffer> <Leader>#h o<Esc>:let @h=snip_newhost->join("\n")<CR>"hp/SNIP_\w\+<CR>
" }}}
" TODO snippet engine:
" input: TEXT
" next N mappings of 'tab' (immediate exit if / != SNIP) will do 'cgn'
" ALWAYS prefix snippets with <Leader>#
" input: key(s)
" }}}
