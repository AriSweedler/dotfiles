let surrounders = [
  \["'","'"],
  \['"','"'],
  \["{","}"],
  \["(",")"],
  \["[","]"],
\]

for sur in surrounders
  execute printf("vnoremap %s c%s%s<esc>P", sur[0], sur[0], sur[1])
endfor
