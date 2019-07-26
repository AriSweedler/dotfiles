let surrounders = [
  \["'","'"],
  \["`","`"],
  \['"','"'],
  \["{","}"],
  \["(",")"],
  \["[","]"],
\]

for sur in surrounders
  execute printf("vnoremap <leader>s%s c%s%s<esc>P", sur[0], sur[0], sur[1])
  execute printf("nnoremap <leader>s%s ciW%s%s<esc>P", sur[0], sur[0], sur[1])
endfor
