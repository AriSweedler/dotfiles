packadd vim-go
setlocal tabstop=2 noexpandtab autoindent
setlocal foldmethod=syntax

nnoremap <buffer> \A /\zs\[ARI]<CR>

" Apex Logging shortcuts {{{
nnoremap <buffer> <Leader>A odefer ilo_log.Action("")()<Left><Left><Left><Left>

iabbrev <buffer> loggy log.WithField("tag", "[ARI]").Info("")<Left><Left>
nnoremap <buffer> <Leader>E 0f.aWithError(err).<ESC>
nnoremap <buffer> <Leader>F 0f.aWithField("xxx", xxx).<ESC>?xxx<Enter>N

" Combine 2 consecutive 'WithField's into 1 'WithFields'
nnoremap <buffer> <Leader><Leader>F 0fWeas(log.Fields{<Enter><ESC> %a<Enter><ESC>dt(%a<Enter>})<ESC>%j^xf,r:A<BS>,<ESC>j^xf,r:A<BS>,<ESC>

" Remove a logging element on this line
nnoremap <buffer> <Leader><Leader><Leader>F F.dt.
" }}}

" Because I use the plugin `vim-go`,,,
try
	unmap <buffer> <C-t>
	unmap <buffer> gdzO
catch
endtry
nmap gd <Leader>to<C-o><C-]>
nmap g<C-]> <Leader>to<C-o><C-]>

" Go to next error, if one exists... (jump down to the window that my LSP
" opens up when compilation fails and enter the first wrong part)
nmap <C-e> <C-w>j<Enter>
