# Shared jq for a working doc's asks table.
# Input: {"asks": [{id, title, needs: [id], status, owner, dispatch?: {vehicle, ref}, updated}]}.
# Rows are unordered on disk; `ordered` flattens the DAG (Kahn, stable on input order).

def statuses: ["todo", "running", "review", "done", "dropped"];
def rows: .asks // [];
def by_id: rows | map({(.id): .}) | add // {};

def topo:
  rows as $rows
  | {order: [], left: ($rows | map(.id)), stuck: false}
  | until((.left | length) == 0 or .stuck;
      . as $s
      | [ $rows[]
          | select(.id as $i | ($s.left | index($i)) != null)
          | select(all((.needs // [])[]; . as $n | ($s.order | index($n)) != null))
          | .id ] as $ready
      | if ($ready | length) == 0 then .stuck = true
        else .order += $ready | .left -= $ready end);

def ordered: topo as $t | by_id as $m | [ $t.order[] | $m[.] ];
def position: ordered | to_entries | map({(.value.id): (.key + 1)}) | add // {};

def violations:
  rows as $rows
  | ($rows | map(.id)) as $ids
  | ([ $rows[] | .id as $id
       | (if ((.needs // []) | index($id)) != null then ["\($id): needs itself"] else [] end)
       + [ (.needs // [])[] | select(. as $n | ($ids | index($n)) == null) | "\($id): needs unknown ask '\(.)'" ]
       + (if (.status as $st | statuses | index($st)) == null then ["\($id): invalid status '\(.status)'"] else [] end)
       + (if (.status == "running" or .status == "review") and ((.owner // "") == "") then ["\($id): \(.status) without owner"] else [] end)
       + (if (.id | test("^[a-z0-9]+(-[a-z0-9]+)*$")) then [] else ["\($id): id is not a kebab-case slug"] end)
       + (if ((.title // "") | split(" ") | map(select(length > 0)) | length) > 8 then ["\($id): title over 8 words"] else [] end)
     ] | add // [])
  + [ $ids | group_by(.) | .[] | select(length > 1) | "\(.[0]): duplicate id" ]
  + (topo as $t | if $t.stuck then ["cycle among: \($t.left | join(", "))"] else [] end);

def settled: .status == "done" or .status == "dropped";
def ready:
  by_id as $m
  | [ rows[] | select(.status == "todo") | select(all((.needs // [])[]; $m[.] | settled)) | .id ];

def unsettled_needs($m): (.needs // []) | map(select($m[.] | settled | not));
def cell_needs($pos; $needs): $needs | map($pos[.]) | sort | map(tostring) | join(", ") | if . == "" then "-" else . end;

# $open hides settled rows and settled Needs; positions stay those of the full table.
def table_md($links; $open):
  position as $pos
  | by_id as $m
  | ["| # | Ask | Needs | Status | Owner |", "|---|---|---|---|---|"]
    + [ ordered[]
        | select(($open | not) or (settled | not))
        | (if $open then unsettled_needs($m) else (.needs // []) end) as $needs
        | "| \($pos[.id]) | \(if $links then "[\(.title)](asks/\(.id).md)" else .title end) | \(cell_needs($pos; $needs)) | \(.status) | \(.owner // "-") |" ]
  | .[];
def table_md($links): table_md($links; false);
def hidden_count: [ rows[] | select(settled) ] | length;

def node_id: gsub("-"; "_");
def mermaid:
  position as $pos
  | ["flowchart LR"]
    + [ ordered[] | "  \(.id | node_id)[\"\($pos[.id]) \(.title)\"]" ]
    + [ ordered[] | .id as $id | (.needs // [])[] | "  \(. | node_id) --> \($id | node_id)" ]
  | .[];
