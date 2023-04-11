" Turn <XYZ>@<ABC> into
"
" Host NEWHOST
"     HOSTNAME ABC
"     USER XYZ
nnoremap <buffer> <Leader>H "adt@x"bd$iHost NEWHOST<CR><Tab>Hostname <C-r>b<CR><Tab>User <C-r>a<ESC>
