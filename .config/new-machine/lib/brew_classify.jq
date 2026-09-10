# Drift classifier for `new-machine brew`. Pure: the whole world arrives as one input object,
# built by brew::classify (lib/brew.zsh), so a test can hand-write it and run `jq -f` directly.
#
#   inventory           brew::inventory output (receipts are the installed universe)
#   alias_map           brew::alias_map output; values are arrays, >1 value means ambiguous
#   declared            {global: {formula,cask,tap,vscode}, local: {...}}   names as written
#   ignore              {global: {entries: [{kind,name,reason}], includes: [{path,reason}]}, local: {...}}
#   include_declared    [{tier, path, reason, present, declared: {formula,cask,tap,vscode}}]
#   tap_info            {"<tap>": {formula_names, cask_tokens}}   only taps `brew tap` lists
#   tap_casks_on_disk   {"<tap>": ["<token>", ...]}   Casks/*.rb under `brew --repository <tap>`
#   trusted_taps        taps declared with `trusted: true` in a tier, or in trust.json trustedtaps
#   previous_undeclared ["<kind>/<name>", ...] from the previous run's last_result.json
#
# `missing` is not computed here: brew_pkgs owns it through `brew bundle check`, so the two
# never disagree. Precedence for an installed item: orphan > declared > ignored > undeclared.

. as $in
| $in.inventory as $inventory
| ($in.alias_map // {}) as $alias_map
| ($in.declared // {}) as $declared
| ($in.ignore // {}) as $ignore
| ($in.include_declared // []) as $include_declared
| ($in.tap_info // {}) as $tap_info
| ($in.tap_casks_on_disk // {}) as $tap_casks_on_disk
| ($in.trusted_taps // []) as $trusted_taps
| ($in.previous_undeclared // []) as $previous_undeclared

| def kinds: ["formula", "cask", "tap", "vscode"];
  def tiers: ["global", "local"];
  def key: .kind + "/" + .name;
  def has_item($xs; $x): any($xs[]; . == $x);
  # Official homebrew/* taps are implicitly trusted and API-backed, so they are neither
  # orphan candidates nor trust findings.
  def third_party($tap): $tap != null and ($tap | startswith("homebrew/") | not);
  def canon($kind; $name):
    if $kind == "tap" then $name
    elif $kind == "vscode" then ($name | ascii_downcase)
    else (($alias_map[$kind] // {})[$name] // []) as $v
         | if ($v | length) == 1 then $v[0] else $name end
    end;
  def tapped($tap): any(($inventory.taps // [])[]; .name == $tap);

  # Only on-request kegs and casks are drift candidates; dependency-only kegs never appear.
  def candidates:
      [ ($inventory.formulae // [])[] | select(.on_request)
        | {kind: "formula", name: .full_name, tap, keg, source_path_exists} ]
    + [ ($inventory.casks // [])[] | select(.on_request)
        | {kind: "cask", name: .token, tap, full_token} ]
    + [ ($inventory.taps // [])[] | {kind: "tap", name, tap: null} ]
    + [ ($inventory.vscode // [])[] | {kind: "vscode", name: (.id | ascii_downcase), tap: null} ];
  # Every installed name, dependency-only kegs included: an ignore naming one is resolvable even
  # though it can never be a drift candidate.
  def installed:
      [ ($inventory.formulae // [])[] | {kind: "formula", name: .full_name} ]
    + [ ($inventory.casks // [])[] | {kind: "cask", name: .token} ]
    + [ ($inventory.taps // [])[] | {kind: "tap", name} ]
    + [ ($inventory.vscode // [])[] | {kind: "vscode", name: (.id | ascii_downcase)} ];

  def declared_canon($tier):
    [ kinds[] as $k | (($declared[$tier] // {})[$k] // [])[]
      | {kind: $k, name: canon($k; .), raw: ., tier: $tier} ];
  def include_canon:
    [ $include_declared[] | select(.present) | . as $inc | kinds[] as $k
      | (($inc.declared // {})[$k] // [])[]
      | {kind: $k, name: canon($k; .), raw: ., tier: $inc.tier, reason: $inc.reason,
         via: ("include-declared " + $inc.path)} ];
  def line_ignores:
    [ tiers[] as $t | (($ignore[$t] // {}).entries // [])[]
      | {kind, name: canon(.kind; .name), raw: .name, reason, tier: $t, via: "line"} ];

  # A third-party keg whose formula file is gone, or that its tap no longer lists as a formula,
  # cannot be reinstalled on a fresh machine. Core kegs are never checked (that needs the API).
  # The formula_names test applies only when tap-info answered for that tap.
  def is_orphan($f):
    third_party($f.tap) and (
      ($f.source_path_exists | not)
      or (($tap_info | has($f.tap))
          and (has_item($tap_info[$f.tap].formula_names // []; $f.name) | not)));
  def orphan_hint($f):
    if (tapped($f.tap) | not) then "tap not tapped"
    elif has_item(($tap_info[$f.tap] // {}).cask_tokens // []; $f.name)
         or has_item($tap_casks_on_disk[$f.tap] // []; $f.keg)
      then "the tap now ships cask " + $f.name
    else "formula removed from tap" end;

  candidates as $cands
| installed as $installed
| [ $cands[] | select(.kind == "formula" and is_orphan(.)) ] as $orphans
| ($orphans | map(.name)) as $orphan_names
| [ tiers[] as $t | declared_canon($t)[] ] as $decl
| ($decl | map(key)) as $decl_keys
| include_canon as $inc
| line_ignores as $lig
| [ $cands[] | . as $c
    | if $c.kind == "formula" and has_item($orphan_names; $c.name) then $c + {class: "orphan"}
      elif has_item($decl_keys; $c | key) then $c + {class: "declared"}
      else ([ $lig[] | select(.kind == $c.kind and .name == $c.name) ]
            + [ $inc[] | select(.kind == $c.kind and .name == $c.name) ]) as $m
           | if ($m | length) > 0 then $c + {class: "ignored", match: $m[0]}
             else $c + {class: "undeclared"} end
      end ] as $classified

| {
    undeclared: [ $classified[] | select(.class == "undeclared") | (key) as $k
      | {kind, name, tap, problem: "installed but undeclared",
         new: (has_item($previous_undeclared; $k) | not)}
        + (if .full_token != null then {full_token} else {} end) ],
    orphan_keg: [ $orphans[] | {kind, name, tap, problem: "orphaned", hint: orphan_hint(.)} ],
    declared_orphan: [ $decl[] | select(.kind == "formula" and has_item($orphan_names; .name))
      | {kind, name, tier, raw, problem: "declared orphan"} ],
    duplicate: ( $decl | group_by(key) | map(select(length > 1)
      | {kind: .[0].kind, name: .[0].name, problem: "declared twice", tiers: map(.tier)}) ),
    ignored: [ $classified[] | select(.class == "ignored")
      | {kind, name, tier: .match.tier, reason: .match.reason, via: .match.via} ],
    redundant_ignore: [ $classified[] | select(.class == "declared") | . as $c
      | $lig[] | select(.kind == $c.kind and .name == $c.name) | {kind, name, tier} ],
    unresolvable_ignore: [ $lig[] | . as $e
      | select(any($installed[]; .kind == $e.kind and .name == $e.name) | not)
      | {kind, name: .raw, tier, reason} ],
    include_declared_missing: [ $include_declared[] | select(.present | not) | {tier, path} ],
    ambiguous_alias: [ ["formula", "cask"][] as $k | ($alias_map[$k] // {}) | to_entries[]
      | select(.value | length > 1) | {kind: $k, name: .key, candidates: .value} ],
    untrusted_taps: ( [ $decl[] | select(.kind == "tap" and third_party(.name)
      and (has_item($trusted_taps; .name) | not)) | .name ] | unique ),
    inventory_note: (
      (($inventory.list_full_name // []) | length) as $listed
      | (($inventory.formulae // []) | length) as $kegs
      | if ($inventory | has("list_full_name")) and $listed != $kegs
        then "brew list --formula --full-name reports \($listed) formulae; Cellar receipts report \($kegs)"
        else null end ),
    vscode_skipped: ($inventory.vscode_skipped // false),
    counts: {
      satisfied: ([ $classified[] | select(.class == "declared") ] | length),
      undeclared: ([ $classified[] | select(.class == "undeclared") ] | length),
      ignored: ([ $classified[] | select(.class == "ignored") ] | length)
    }
  }
