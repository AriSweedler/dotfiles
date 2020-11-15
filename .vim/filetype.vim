let map = {}
let map.verilog = '*.tb'
let map.markdown = '*.mdx'
let map.yacc = '*.yacc'
let map.make = 'Makefile.inc'
let map.log = '*.log'

" Give the 'key' filetype to files named 'value'
for ft in map->keys()
  let command = "au BufNewFile,BufRead " . map->get(ft) . " setf " . ft
  execute command
endfor
