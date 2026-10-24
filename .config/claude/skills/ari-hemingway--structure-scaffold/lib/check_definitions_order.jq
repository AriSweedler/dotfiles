# Mechanical check for a scaffold definitions table.
# Input: array of {term, definition} rows in table order (or an object whose .rows / .ordered holds it).
# Args: $max_sentences, $max_words (numbers). Output: one violation string per line.
def norm: ascii_downcase | gsub("[^a-z0-9/]+"; " ") | gsub("^ +| +$"; "");
def re_escape: gsub("(?<c>[.*+?^${}()|\\[\\]\\\\])"; "\\\(.c)");
def mention_re: ascii_downcase | re_escape | gsub("[\\s_-]+"; "[\\s_-]*") | "(^|[^a-z0-9])" + . + "(s|es|ed|d|ing)?(?=$|[^a-z0-9])";
def sentences: [splits("(?<=[.!?])\\s+(?=[A-Z(`/~<])")] | map(select(length > 0));
def words: [splits("\\s+")] | map(select(length > 0)) | length;
def longer_variant($a; $b): ($b|norm|contains($a|norm)) and (($b|norm|length) > ($a|norm|length));
(if type == "object" then (.rows // .ordered) else . end) as $rows
| [ range(0; $rows|length) as $i
    | $rows[$i] as $row
    | $row.definition as $text
    | (if ($text | test($row.term | mention_re; "i")) then ["\($row.term): mentions its own term"] else [] end)
    + [ range($i + 1; $rows|length) as $j
        | $rows[$j] as $other
        | select(longer_variant($row.term; $other.term) | not)
        | select($text | test($other.term | mention_re; "i"))
        | "\($row.term): uses \"\($other.term)\" defined later (row \($j + 1) > row \($i + 1))" ]
    + (($text | sentences) as $s
       | (if ($s|length) > $max_sentences then ["\($row.term): \($s|length) sentences; max \($max_sentences)"] else [] end)
         + [ $s[] | select(words > $max_words) | "\($row.term): \(words)-word sentence; max \($max_words)" ])
    + (if ($text | test("\\betc\\b|\\.\\.\\.|…|\\bvarious\\b|\\band so on\\b"; "i")) then ["\($row.term): vague filler (etc, ..., various, and so on)"] else [] end)
  ]
| add // []
| .[]
