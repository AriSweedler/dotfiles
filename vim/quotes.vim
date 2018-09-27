autocmd FileType *.cpp,*.py,*.[ch],vim :inoremap " <C-r>=QuoteTyped()<CR>

" when programming, typing a quote " will behave differently.
  " ONE: if g:in_quotes and curchar = ", then set g:in_quotes to false
  " TWO: place a pair of quotes "". set g:in_quotes to true
  " THREE: Unless there's an unmatched quote ahead of us on this line
function! QuoteTyped()
  " Eat pre-typed quotes
  if CurChar() == '"' && g:in_quotes
    let g:in_quotes = 0
    return "\<Right>"
  endif

  " Check for an unmatched quote ahead of us.
  let curline = getline('.')
  let removedMatchedQuotes = substitute(curline, '"[^"]*"', '', 'g')
  let loneQuote= stridx(removedMatchedQuotes, '"')
  if l:loneQuote == -1
    let g:in_quotes = 1
    return "\"\"\<Left>"
  else
    " unmatched quote
    let g:in_quotes = 0
    return '"'
  endif
endfunction

echo "quotes.vim sourced"

