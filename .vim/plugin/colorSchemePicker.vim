""" A color scheme picker
let g:Color_scheme_picker_open = 0
let g:Color_scheme_picker_selected = ''

function! Color_scheme_picker()
  if g:Color_scheme_picker_open == 1
    echo "'Color scheme picker' is alread open!"
    return
  endif

  let g:Color_scheme_picker_open = 1
  let g:Color_scheme_picker_selected = trim(execute('color'))

  " Open up a new window, up to 25 lines tall, named 'color_scheme_picker'
  let l:colors = getcompletion('', 'color')
  execute min([len(l:colors), 25]) . "new color_scheme_picker"
  setlocal nobuflisted buftype=nofile bufhidden=wipe noswapfile
  " Highlight this buffer differently. Do that by defining a syntax region.
  " It's not perfect... like it wont get number colomn and stuff. 
  " but... whatever if it works for now.
  " TODO yea this isn't working yet lol
  "syntax region Everything start=+^+  skip=+.*+  end=+.+
  "syntax match everything "^.*$"
  "highlight! everything term=bold ctermfg=Black ctermbg=White

  " Place all the possible colorschemes into the buffer.
  " Delete the first line (it's blank), and move the cursor up to the top
  put = l:colors
  execute '1d'
endfunction

function! Close_Color_scheme_picker()
  let g:Color_scheme_picker_open = 0
  execute 'color ' . g:Color_scheme_picker_selected
  redraw!
  echo 'Selected color scheme "' . g:Color_scheme_picker_selected . '".'
endfunction

function! Maybe_update_color()
  let l:current_color = trim(execute('color'))
  let l:selected = getline('.')

  if l:selected != l:current_color
    let l:changed = 0

    try
      execute 'color ' . l:selected
      let l:changed = 1
    catch /.*/
      execute 'color ' . g:Color_scheme_picker_selected
    finally
      redraw!
      if l:changed == 1
        echo 'Color scheme "' . l:selected . '"'
      else
        echom 'No such color scheme "' . l:selected . '" -- showing "' . g:Color_scheme_picker_selected . '"'
      endif
    endtry
  endif
endfunction

function! Select_Color_scheme()
  let g:Color_scheme_picker_selected = trim(execute('color'))
  execute 'q'
endfunction

autocmd BufWipeout color_scheme_picker call Close_Color_scheme_picker()
autocmd CursorMoved color_scheme_picker call Maybe_update_color()
autocmd BufEnter color_scheme_picker nnoremap <buffer> <silent> <CR> :call Select_Color_scheme()<CR>

command! ColorSchemePicker call Color_scheme_picker()
