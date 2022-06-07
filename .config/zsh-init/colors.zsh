# Fun little function to print a colormap
function colors() {
  for i in {0..255}; do
    print -Pn "%K{$i} %k%F{$i}${(l:3::0:)i}%f " ${${(M)$((i%8)):#7}:+$'\n'}
  done
}
