setlocal tabstop=2 softtabstop=2 shiftwidth=2 expandtab
setlocal autoindent

iabbrev defunn ; FUNCNAME FUNCARGS
\<CR>; ARG-DESCRIPTION
\<CR>; RETURN-DESCRIPTION
\<CR>;
\<CR>; STRATEGY-DESCRIPTION
\<CR>(defun FUNCNAME (FUNCARGS)
\<CR><C-o>ms
\<CR>)<C-o><
\<CR>; TEST CASES
\<CR>(assert (equal (FUNCNAME TEST) RESULT))
\<CR>(assert (equal (FUNCNAME TEST) RESULT))<CR>
\<C-c>V?; FUNCNAME<CR>zf<CR>zo

echom "sourced"
