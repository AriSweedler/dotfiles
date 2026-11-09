# The Raycast snippet tiers, merged: the one object raycast_snippets reads. Builtins only, so the
# shell tests evaluate this same file (`nix eval --impure --json --expr`) without nixpkgs.
#
# Input: tiers, shared first and local last, each { label; path; source }: path is the file people
# edit, source the file read (null when it does not exist).
# Output: { value; errors; }. value is { entries; tiers; files; sources; hashes; }:
#   entries  every snippet ({name, text, keyword?, description?}), a later tier's entry replacing
#            an earlier one of the same name, by keyword in byte order, keyword-less last by name
#   tiers    name → the tiers that hold it, winner first ("local>shared")
#   files    name → the winning tier's path
#   sources  label → path
#   hashes   path → sha256 of what was read ("" for a missing file), so the script can tell when
#            a tier file changed since this merge
# errors names every duplicate name within one file and every keyword two snippets share.
{ tiers }:
let
  fields = [ "name" "text" "keyword" "description" ];
  normalize = e: builtins.listToAttrs (builtins.concatMap
    (n: if e ? ${n} && e.${n} != null && e.${n} != "" then [{ name = n; value = e.${n}; }] else [ ])
    fields);
  uniq = builtins.foldl' (acc: x: if builtins.elem x acc then acc else acc ++ [ x ]) [ ];
  raw = t: if t.source == null then [ ] else builtins.fromJSON (builtins.readFile t.source);
  # Exact duplicates collapse, as they would in one Raycast import.
  read = t: uniq (map normalize (raw t));

  count = x: xs: builtins.length (builtins.filter (y: y == x) xs);
  dupes = xs: builtins.filter (x: count x xs > 1) xs;

  typeErrors = builtins.concatMap
    (t: if builtins.isList (raw t) && builtins.all (e: builtins.isAttrs e
          && builtins.isString (e.name or null) && builtins.isString (e.text or null)
          && builtins.all (f: !(e ? ${f}) || e.${f} == null || builtins.isString e.${f}) [ "keyword" "description" ])
          (raw t)
        then [ ]
        else [ "Not a snippets array (string name and text; keyword and description strings when present) | file='${t.path}'" ])
    tiers;
  dupeErrors = builtins.concatMap
    (t: let names = uniq (dupes (map (e: e.name) (read t))); in
      if names == [ ] then [ ]
      else [ "Duplicate snippet names in one file | names='${builtins.concatStringsSep ", " names}' file='${t.path}'" ])
    tiers;

  byName = builtins.foldl'
    (acc: t: builtins.foldl'
      (a: e: a // {
        ${e.name} = {
          entry = e;
          tier = if a ? ${e.name} then "${t.label}>${a.${e.name}.tier}" else t.label;
          file = t.path;
        };
      })
      acc
      (read t))
    { }
    tiers;
  names = builtins.attrNames byName;

  rank = e: if e ? keyword then 0 else 1;
  before = a: b:
    if rank a != rank b then rank a < rank b
    else if (a.keyword or "") != (b.keyword or "") then (a.keyword or "") < (b.keyword or "")
    else a.name < b.name;
  entries = builtins.sort before (map (n: byName.${n}.entry) names);

  # Tier order, first appearance first: how a clash names its snippets.
  inOrder = map (n: byName.${n}.entry) (uniq (builtins.concatMap (t: map (e: e.name) (read t)) tiers));
  keyed = builtins.filter (e: e ? keyword) inOrder;
  clashes = map
    (k: "${k}: " + builtins.concatStringsSep " and "
      (map (e: "${e.name} (${byName.${e.name}.file})") (builtins.filter (e: e.keyword == k) keyed)))
    (uniq (dupes (map (e: e.keyword) keyed)));
  clashErrors = if clashes == [ ] then [ ]
    else [ "Two snippets share a keyword | collisions='${builtins.concatStringsSep "; " clashes}'" ];
in
{
  value = if typeErrors != [ ] then { } else {
    inherit entries;
    tiers = builtins.listToAttrs (map (n: { name = n; value = byName.${n}.tier; }) names);
    files = builtins.listToAttrs (map (n: { name = n; value = byName.${n}.file; }) names);
    sources = builtins.listToAttrs (map (t: { name = t.label; value = t.path; }) tiers);
    hashes = builtins.listToAttrs (map
      (t: { name = t.path; value = if t.source == null then "" else builtins.hashFile "sha256" t.source; })
      tiers);
  };
  # A type error stops here: nothing else can be read from that file.
  errors = if typeErrors != [ ] then typeErrors else dupeErrors ++ clashErrors;
}
