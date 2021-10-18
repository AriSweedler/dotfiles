let my_map = {}
let my_map.verilog = '*.tb'
let my_map.markdown = '*.mdx'
let my_map.yacc = '*.yacc'
let my_map.make = 'Makefile.inc'
let my_map.spec = '*.spec*'
let my_map.log = '*.log,*.log.old'
let my_map.strace = '*.truss,*.strace,*.strace.*'

" Give the 'key' filetype to files named according to the pattern 'pat'
for [ft, pat] in my_map->items()
  let command = "autocmd BufNewFile,BufRead " . pat . " setfiletype " . ft
  execute command
endfor
