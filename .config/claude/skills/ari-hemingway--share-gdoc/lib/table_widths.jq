# Choose column widths for every two-column table so the table is as short as possible.
#
# Input: a Docs API document JSON with body.content and documentStyle.
# Output: one object per two-column table:
#   {start, rows, text_width, current: {w0, w1, lines}, best: {w0, w1, lines}}
#
# Model: Docs renders imported markdown in Arial 11pt, which is metric-compatible with
# Helvetica, so the AFM widths below (per 1000 em) predict the advance of each character.
# Code spans render in a monospace face at 600/1000 em. Each cell has 5pt padding on both
# sides. A row is as tall as its tallest cell, and a cell's height is its greedy word-wrap
# line count, so table height is the sum over rows of the per-row maximum. The search tries
# every whole-point split of the table width and keeps the split with the fewest lines. Many
# splits tie, because a term wrapping costs nothing while its definition is taller; ties go to
# the widest Word column, so terms stay on one line wherever that is free.

def helvetica: {
  " ":278,"!":278,"\"":355,"#":556,"$":556,"%":889,"&":667,"'":191,"(":333,")":333,"*":389,"+":584,
  ",":278,"-":333,".":278,"/":278,"0":556,"1":556,"2":556,"3":556,"4":556,"5":556,"6":556,"7":556,
  "8":556,"9":556,":":278,";":278,"<":584,"=":584,">":584,"?":556,"@":1015,
  "A":667,"B":667,"C":722,"D":722,"E":667,"F":611,"G":778,"H":722,"I":278,"J":500,"K":667,"L":556,
  "M":833,"N":722,"O":778,"P":667,"Q":778,"R":722,"S":667,"T":611,"U":722,"V":667,"W":944,"X":667,
  "Y":667,"Z":611,"[":278,"\\":278,"]":278,"^":469,"_":556,"`":222,
  "a":556,"b":556,"c":500,"d":556,"e":556,"f":278,"g":556,"h":556,"i":222,"j":222,"k":500,"l":222,
  "m":833,"n":556,"o":556,"p":556,"q":556,"r":333,"s":500,"t":278,"u":556,"v":500,"w":722,"x":500,
  "y":500,"z":500,"{":334,"|":260,"}":334,"~":584
};

def is_mono($run): (($run.textStyle.weightedFontFamily.fontFamily // "") | test("Mono|Courier|Consolas|Menlo"));

# Width in points of one string in one run.
def text_width($s; $mono; $size):
  if $mono then ($s | length) * 600 * $size / 1000
  else ([ $s | explode[] | [.] | implode | (helvetica[.] // 556) ] | add // 0) * $size / 1000 end;

# Tokens of one paragraph: [{w}] one per space-separated word, widths already in points.
def paragraph_tokens($p):
  [ $p.elements[]
    | select(.textRun != null)
    | .textRun as $r
    | ($r.textStyle.fontSize.magnitude // 11) as $size
    | is_mono($r) as $mono
    | ($r.content | rtrimstr("\n") | split(" ")[] | select(. != ""))
    | {w: text_width(.; $mono; $size)} ];

# Greedy wrap: lines a token list needs inside $avail points. A token wider than the column
# breaks mid-word, which Docs also does.
def wrap_lines($tokens; $avail):
  if ($tokens | length) == 0 then 1
  else
    ($tokens | map(.w)) as $ws
    | (278 * 11 / 1000) as $space
    | reduce $ws[] as $tw ({lines: 1, cur: 0};
        if .cur == 0 then .cur = $tw
        elif .cur + $space + $tw <= $avail then .cur += $space + $tw
        else .lines += 1 | .cur = $tw end)
    | .lines + ([ $ws[] | select(. > $avail) | (. / $avail | ceil) - 1 ] | add // 0)
  end;

def cell_lines($cell; $avail):
  [ $cell.content[] | select(.paragraph != null) | wrap_lines(paragraph_tokens(.paragraph); $avail) ] | add // 1;

def cell_max_token($cell):
  [ $cell.content[] | select(.paragraph != null) | paragraph_tokens(.paragraph)[] | .w ] | max // 0;

def table_lines($t; $w0; $w1):
  [ $t.tableRows[] | [ cell_lines(.tableCells[0]; $w0 - 10), cell_lines(.tableCells[1]; $w1 - 10) ] | max ] | add;

(.documentStyle) as $ds
| (($ds.pageSize.width.magnitude - $ds.marginLeft.magnitude - $ds.marginRight.magnitude) | floor) as $T
| [ .body.content[] | select(.table != null and .table.columns == 2) | .table as $t
    | ([ $t.tableRows[] | cell_max_token(.tableCells[0]) ] | max) as $min0
    | ([ $t.tableRows[] | cell_max_token(.tableCells[1]) ] | max) as $min1
    | (($min0 + 10 + 1) | ceil) as $lo
    | (($T - $min1 - 10 - 1) | floor) as $hi
    | (($t.tableStyle.tableColumnProperties // []) | map(.width.magnitude // ($T / 2))) as $cur
    | ($cur[0] // ($T / 2)) as $cw0
    | ($cur[1] // ($T - $cw0)) as $cw1
    | ([ range($lo; $hi + 1) | {w0: ., w1: ($T - .), lines: table_lines($t; .; $T - .)} ]
       | sort_by(.lines, -.w0) | .[0]) as $best
    | { start: .startIndex, rows: $t.rows, text_width: $T,
        search: {lo: $lo, hi: $hi},
        current: {w0: $cw0, w1: $cw1, lines: table_lines($t; $cw0; $cw1)},
        best: $best } ]
