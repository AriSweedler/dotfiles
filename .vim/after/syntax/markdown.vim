" Conceal the URL of markdown links
" And have markdownLink regions end upon ')' OR whitespace ==> forgetting a
" closing parenthesis won't screw the whole file up
syntax match markdownUrl "\S\+" nextgroup=markdownUrlTitle skipwhite contained conceal cchar=x
syntax region markdownLink matchgroup=markdownLinkDelimiter start="(" end="\()\|\_s\)" contains=markdownUrl keepend contained
highlight Conceal ctermfg=15 ctermbg=90
