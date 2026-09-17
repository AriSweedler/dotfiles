#!/usr/bin/env python3
"""Cluster a scaffold's discover graph into subsystems and split the refined table.
Run: zsh $HOME/.claude/skills/ari-hemingway--structure-scaffold/bin/cluster_definitions.zsh --help

Graph: every discover term is a node; each entry in a term's depends_on list is a directed
edge term -> dependency. Communities: greedy modularity (Clauset-Newman-Moore) on the
undirected graph, stopped at the modularity peak, ties broken by row order. Each community
is re-clustered once on its induced subgraph to propose headings inside its article.
Communities under the size floor, and those named by --merge, fold into the neighbour they
share the most edges with.
Refined rows inherit their discover term's community. A row is universal when at least
--universal-ratio of its dependents sit outside its community and it has at least
--universal-floor dependents. The universal set is then closed under mentions with the
matcher of lib/check_definitions_order.jq (whole word, plural and -ed/-ing forms): a row
that a universal row's definition names is promoted too, so a glossary row never leans on a
hoisted row; --universal TERM seeds that closure with a row the articles' prose shares. With --min-rows N, a community left with fewer than N hoisted rows merges into
its most-connected neighbour; by default no community merges on row count, since an article
may define no new terms. Universal rows form the glossary; the rest hoist into articles.
"""
import argparse
import json
import re
from collections import Counter
from pathlib import Path

from at_log import log_info, log_warn, die

DEFAULT_UNIVERSAL_RATIO = 0.5
DEFAULT_MIN_ROWS = 0  # --min-rows off: an article may hoist no rows and run on glossary vocabulary alone
UNIVERSAL_FLOOR_DIVISOR = 15  # floor = nodes / 15: about 20 dependents on a 300-node graph
TINY_FRACTION = 0.02  # communities under 2% of the nodes merge into a neighbour
MIN_SECTION_SPLIT = 12  # communities smaller than this get no section split
MIN_SECTION_SIZE = 2  # sections smaller than this merge into a sibling section
CLUSTER_EDGES_PER_NODE = 2  # cluster-diagram edges kept: about this many per community
CORE_SIZE = 3  # name candidates shown per community
GLOSSARY_PREVIEW = 10  # universal terms drawn in the cluster diagram
EXPECTED_UNIVERSAL_SHARE = (0.15, 0.6)  # outside this share the clustering is off
RE_SPECIAL = set(".*+?^${}()|[]\\")  # the characters lib/check_definitions_order.jq escapes


def norm(text):
    return re.sub(r"[^a-z0-9/]+", " ", text.lower()).strip()


def singular(key):
    if key.endswith("s"):
        return key[:-1]
    return key


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "cluster"


def mermaid_label(text):
    return text.replace('"', "#quot;")


def re_escape(text):
    return "".join("\\" + char if char in RE_SPECIAL else char for char in text)


def mention_re(term):
    """Whole-word match of a term and its plural / -ed / -ing forms; mirrors lib/check_definitions_order.jq."""
    core = re.sub(r"[\s_-]+", r"[\\s_-]*", re_escape(term.lower()))
    return re.compile(r"(^|[^a-z0-9])" + core + r"(s|es|ed|d|ing)?(?=$|[^a-z0-9])", re.IGNORECASE)


def longer_variant(short, longer):
    """True when longer is short with words around it (NAT, Symmetric NAT); the checker skips such pairs."""
    return norm(short) in norm(longer) and len(norm(longer)) > len(norm(short))


def read_json(path):
    file_path = Path(path)
    if not file_path.is_file():
        die(f"input not found | path='{file_path}'")
    return json.loads(file_path.read_text(encoding="utf-8"))


def unwrap_list(body, keys, path):
    if isinstance(body, list):
        return body
    for key in keys:
        if isinstance(body, dict) and isinstance(body.get(key), list):
            return body[key]
    die(f"unrecognized JSON shape | path='{path}' expected='a list or an object with one of {', '.join(keys)}'")


def load_terms(path):
    items = unwrap_list(read_json(path), ("definitions", "rows", "ordered"), path)
    terms = []
    for item in items:
        if item.get("drop"):
            continue
        terms.append({
            "term": item["term"],
            "definition": item.get("definition", ""),
            "doc_url": item.get("doc_url", ""),
            "depends_on": [d for d in item.get("depends_on", []) if isinstance(d, str)],
        })
    if not terms:
        die(f"no terms loaded | path='{path}'")
    return terms


def load_rows(path):
    items = unwrap_list(read_json(path), ("rows", "ordered", "definitions"), path)
    return [{"term": r["term"], "definition": r.get("definition", ""), "doc_url": r.get("doc_url", "")} for r in items]


def term_index(terms):
    index = {}
    for i, term in enumerate(terms):
        index.setdefault(norm(term["term"]), i)
    return index


def lookup(index, name):
    key = norm(name)
    if key in index:
        return index[key]
    return index.get(singular(key))


def build_graph(terms):
    """Directed deps[i] = {j} for each resolvable depends_on entry; adj = undirected weights."""
    index = term_index(terms)
    deps = [set() for _ in terms]
    unresolved = 0
    for i, term in enumerate(terms):
        for name in term["depends_on"]:
            j = lookup(index, name)
            if j is None:
                unresolved += 1
                continue
            if j != i:
                deps[i].add(j)
    adj = [Counter() for _ in terms]
    for i, targets in enumerate(deps):
        for j in targets:
            adj[i][j] += 1
            adj[j][i] += 1
    edge_count = sum(len(targets) for targets in deps)
    log_info(f"graph built | nodes='{len(terms)}' edges='{edge_count}' unresolved_depends_on='{unresolved}'")
    return deps, adj


def induced(adj, nodes):
    position = {v: k for k, v in enumerate(nodes)}
    return [Counter({position[u]: w for u, w in adj[v].items() if u in position}) for v in nodes]


def greedy_modularity(adj):
    """Clauset-Newman-Moore agglomeration; stops at the modularity peak. Returns member lists."""
    n = len(adj)
    two_m = sum(sum(w.values()) for w in adj)
    if two_m == 0:
        return [[i] for i in range(n)]
    a = {i: sum(adj[i].values()) / two_m for i in range(n)}
    e = {i: {j: w / two_m for j, w in adj[i].items()} for i in range(n)}
    comm = {i: [i] for i in range(n)}
    while len(comm) > 1:
        best, pair = 0.0, None
        for c in sorted(comm):
            for d in sorted(e[c]):
                if d <= c:
                    continue
                gain = 2 * (e[c][d] - a[c] * a[d])
                if gain > best + 1e-12:
                    best, pair = gain, (c, d)
        if pair is None:
            break
        c, d = pair
        comm[c].extend(comm.pop(d))
        for x, w in e.pop(d).items():
            if x == d:
                continue
            e[x].pop(d, None)
            if x == c:
                continue
            e[c][x] = e[c].get(x, 0.0) + w
            e[x][c] = e[x].get(c, 0.0) + w
        a[c] += a.pop(d)
    return [sorted(members) for _, members in sorted(comm.items())]


def modularity(adj, clusters):
    two_m = sum(sum(w.values()) for w in adj)
    if two_m == 0:
        return 0.0
    q = 0.0
    for members in clusters:
        inside = set(members)
        internal = sum(w for i in members for j, w in adj[i].items() if j in inside)
        degree = sum(sum(adj[i].values()) for i in members)
        q += internal / two_m - (degree / two_m) ** 2
    return q


def choose_merge_target(weights, source, count):
    if weights:
        return max(sorted(weights), key=lambda k: weights[k])
    return min(k for k in range(count) if k != source)


def most_connected(adj, clusters, source):
    """Index of the community that shares the most edge weight with clusters[source]."""
    cluster_of = {v: ci for ci, members in enumerate(clusters) for v in members}
    weights = Counter()
    for v in clusters[source]:
        for u, w in adj[v].items():
            target = cluster_of.get(u)
            if target is not None and target != source:
                weights[target] += w
    return choose_merge_target(weights, source, len(clusters))


def merge_tiny(adj, clusters, min_size):
    """Merge every group under min_size into the group it shares the most edges with (used for sections)."""
    clusters = [list(members) for members in clusters]
    while len(clusters) > 1:
        tiny = [ci for ci, members in enumerate(clusters) if len(members) < min_size]
        if not tiny:
            break
        source = min(tiny, key=lambda k: (len(clusters[k]), k))
        target = most_connected(adj, clusters, source)
        clusters[target].extend(clusters[source])
        del clusters[source]
    return [sorted(members) for members in clusters]


def rank_members(deps, members):
    """Members by in-degree from cluster-mates, highest first; ties by row order."""
    inside = set(members)
    in_degree = Counter()
    for i in members:
        for j in deps[i]:
            if j in inside:
                in_degree[j] += 1
    return sorted(members, key=lambda j: (-in_degree[j], j))


def community_name(terms, deps, members):
    return terms[rank_members(deps, members)[0]]["term"]


def split_sections(adj, members):
    if len(members) < MIN_SECTION_SPLIT:
        return [members]
    parts = greedy_modularity(induced(adj, members))
    if len(parts) < 2:
        return [members]
    sections = [sorted(members[k] for k in part) for part in parts]
    return merge_tiny(adj, sections, MIN_SECTION_SIZE)


class Communities:
    """The partition of the discover graph plus the merge history that lets a former name still address a community."""

    def __init__(self, terms, deps, adj, clusters):
        self.terms = terms
        self.deps = deps
        self.adj = adj
        self.clusters = [sorted(members) for members in clusters]
        self.aliases = [set() for _ in self.clusters]
        self.merged = []

    def name(self, index):
        return community_name(self.terms, self.deps, self.clusters[index])

    def names(self):
        return [self.name(ci) for ci in range(len(self.clusters))]

    def cluster_of(self):
        return {v: ci for ci, members in enumerate(self.clusters) for v in members}

    def sort(self):
        order = sorted(range(len(self.clusters)), key=lambda ci: (-len(self.clusters[ci]), self.clusters[ci][0]))
        self.clusters = [self.clusters[ci] for ci in order]
        self.aliases = [self.aliases[ci] for ci in order]

    def merge(self, source, target, reason):
        """Fold community source into target; both former names stay addressable by --merge and --rename."""
        from_name, into_name = self.name(source), self.name(target)
        self.merged.append({"from": from_name, "into": into_name, "reason": reason})
        log_info(f"merged | from='{from_name}' into='{into_name}' reason='{reason}'")
        self.aliases[target] |= self.aliases[source] | {from_name, into_name}
        self.clusters[target] = sorted(self.clusters[target] + self.clusters[source])
        del self.clusters[source]
        del self.aliases[source]

    def former_names(self, index):
        current = norm(self.name(index))
        return sorted(alias for alias in self.aliases[index] if norm(alias) != current)

    def resolve(self, label):
        """Index of the community whose current name, slug, or former name is label; dies otherwise."""
        key = norm(label)
        names = self.names()
        matches = [
            ci for ci, name in enumerate(names)
            if key in {norm(name), norm(slugify(name))} or key in {norm(alias) for alias in self.aliases[ci]}
        ]
        if not matches:
            die(f"unknown community | community='{label}' valid='{', '.join(names)}'")
        if len(matches) > 1:
            die(f"ambiguous community | community='{label}' matches='{', '.join(names[ci] for ci in matches)}'")
        return matches[0]


def merge_small(state, min_size):
    """Fold every community under min_size members into its most-connected neighbour."""
    while len(state.clusters) > 1:
        small = [ci for ci, members in enumerate(state.clusters) if len(members) < min_size]
        if not small:
            return
        source = min(small, key=lambda ci: (len(state.clusters[ci]), ci))
        state.merge(source, most_connected(state.adj, state.clusters, source), "min_size")


def parse_pairs(values, flag, expected):
    pairs = []
    for value in values:
        left, sep, right = value.partition("=")
        left, right = left.strip(), right.strip()
        if not sep or not left or not right:
            die(f"invalid {flag} | {flag}='{value}' expected='{expected}'")
        pairs.append((left, right))
    return pairs


def parse_aliases(values):
    return {norm(left): right for left, right in parse_pairs(values, "--alias", "REFINED TERM=DISCOVER TERM")}


def apply_user_merges(state, pairs):
    for left, right in pairs:
        source, target = state.resolve(left), state.resolve(right)
        if source == target:
            die(f"cannot merge a community into itself | merge='{left}={right}'")
        state.merge(source, target, "user")


def apply_renames(state, pairs):
    """Current names with the user's renames applied; core lists and membership are untouched."""
    names = state.names()
    for left, right in pairs:
        index = state.resolve(left)
        log_info(f"renamed | community='{names[index]}' new_name='{right}'")
        names[index] = right
    return names


def resolve_rows(rows, labels):
    """Row indices for the --universal terms; dies on a term the accepted table lacks."""
    index = {norm(row["term"]): i for i, row in enumerate(rows)}
    found = []
    for label in labels:
        i = index.get(norm(label))
        if i is None:
            die(f"unknown row | universal='{label}' valid='{', '.join(row['term'] for row in rows)}'")
        found.append(i)
    return found


def force_universal(assignments, forced):
    """Mark the user's --universal rows before the closure so their dependencies are promoted too."""
    for i in forced:
        if assignments[i]["cluster"] is None:
            continue
        assignments[i]["universal"] = True
        assignments[i]["reason"] = "user"


def map_rows(rows, terms, aliases):
    index = term_index(terms)
    nodes = []
    for row in rows:
        name = aliases.get(norm(row["term"]), row["term"])
        node = lookup(index, name)
        if node is None:
            log_warn(f"refined row has no discover term | term='{row['term']}' hint='--alias \"{row['term']}=<discover term>\"'")
        nodes.append(node)
    return nodes


def dependents_by_cluster(deps, cluster_of):
    counts = [Counter() for _ in deps]
    for i, targets in enumerate(deps):
        for j in targets:
            counts[j][cluster_of.get(i)] += 1
    return counts


def is_universal(counts, node, cluster, ratio, floor):
    total = sum(counts[node].values())
    if total < floor:
        return False
    outside = total - counts[node].get(cluster, 0)
    return outside >= ratio * total


def assign_rows(rows, nodes, cluster_of, counts, ratio, floor):
    """Per row: {cluster: id or None, universal: bool, reason: unmapped | isolated | graph}."""
    assignments = []
    for row, node in zip(rows, nodes):
        if node is None:
            assignments.append({"cluster": None, "universal": True, "reason": "unmapped"})
            continue
        cluster = cluster_of.get(node)
        if cluster is None:
            assignments.append({"cluster": None, "universal": True, "reason": "isolated"})
            continue
        assignments.append({"cluster": cluster, "universal": is_universal(counts, node, cluster, ratio, floor), "reason": "graph"})
    return assignments


def close_universal(rows, assignments):
    """Promote every hoisted row a universal row's definition mentions, until no glossary row leans on a hoisted one."""
    patterns = [mention_re(row["term"]) for row in rows]
    promoted = []
    changed = True
    while changed:
        changed = False
        for row, assignment in zip(rows, assignments):
            if not assignment["universal"]:
                continue
            for j, (other, other_assignment) in enumerate(zip(rows, assignments)):
                if other_assignment["universal"] or longer_variant(row["term"], other["term"]):
                    continue
                if not patterns[j].search(row["definition"]):
                    continue
                other_assignment["universal"] = True
                other_assignment["reason"] = "closure"
                promoted.append({"term": other["term"], "because_of": row["term"]})
                changed = True
    return promoted


def thin_community(state, rows, assignments, min_rows):
    """Index of the community hoisting the fewest rows when that count is under min_rows; None otherwise."""
    if not rows or len(state.clusters) < 2:
        return None
    hoisted = Counter(a["cluster"] for a in assignments if not a["universal"] and a["cluster"] is not None)
    thin = [ci for ci in range(len(state.clusters)) if hoisted[ci] < min_rows]
    if not thin:
        return None
    return min(thin, key=lambda ci: (hoisted[ci], len(state.clusters[ci]), ci))


def assign_and_merge_thin(state, rows, nodes, forced, ratio, floor, min_rows):
    """Assign rows, force the user's universal rows, close the glossary, fold thin communities; repeat until stable."""
    while True:
        counts = dependents_by_cluster(state.deps, state.cluster_of())
        assignments = assign_rows(rows, nodes, state.cluster_of(), counts, ratio, floor)
        force_universal(assignments, forced)
        promoted = close_universal(rows, assignments)
        source = thin_community(state, rows, assignments, min_rows)
        if source is None:
            return assignments, promoted
        state.merge(source, most_connected(state.adj, state.clusters, source), "min_rows")


def cross_article_mentions(rows, assignments, names):
    """Hoisted rows whose definition names a row hoisted into another article; the review rules flag these."""
    patterns = [mention_re(row["term"]) for row in rows]
    found = []
    for row, assignment in zip(rows, assignments):
        if assignment["universal"]:
            continue
        for j, (other, other_assignment) in enumerate(zip(rows, assignments)):
            if other_assignment["universal"] or other_assignment["cluster"] == assignment["cluster"]:
                continue
            if longer_variant(row["term"], other["term"]) or not patterns[j].search(row["definition"]):
                continue
            record = {"term": row["term"], "article": names[assignment["cluster"]], "mentions": other["term"], "defined_in": names[other_assignment["cluster"]]}
            found.append(record)
            log_warn(f"cross-article mention | term='{record['term']}' article='{record['article']}' mentions='{record['mentions']}' defined_in='{record['defined_in']}' hint='--merge the two communities or reword the row; review flags it otherwise'")
    return found


def cluster_edges(deps, cluster_of, cluster_count):
    """Directed cross-community dependency counts, strongest first, and the keep threshold."""
    weights = Counter()
    for i, targets in enumerate(deps):
        for j in targets:
            ci, cj = cluster_of.get(i), cluster_of.get(j)
            if ci is None or cj is None or ci == cj:
                continue
            weights[(ci, cj)] += 1
    ranked = sorted(weights.items(), key=lambda kv: (-kv[1], kv[0]))
    keep = CLUSTER_EDGES_PER_NODE * cluster_count
    if not ranked:
        return [], 0
    threshold = ranked[min(keep, len(ranked)) - 1][1]
    return [(ci, cj, w) for (ci, cj), w in ranked], threshold


def cluster_mermaid(clusters_out, edges, threshold, glossary_terms):
    lines = ["flowchart LR"]
    for cluster in clusters_out:
        lines.append(f'  C{cluster["id"]}["{mermaid_label(cluster["name"])}<br/>{cluster["size"]} terms"]')
    for ci, cj, w in edges:
        if w >= threshold:
            lines.append(f"  C{ci} -- {w} --> C{cj}")
    if glossary_terms:
        lines.append('  subgraph U["Glossary (universal)"]')
        for k, term in enumerate(glossary_terms[:GLOSSARY_PREVIEW]):
            lines.append(f'    U{k}(["{mermaid_label(term)}"])')
        lines.append("  end")
    return "\n".join(lines) + "\n"


def write_text(path, text, force):
    out_path = Path(path)
    if out_path.exists() and not force:
        die(f"output exists | path='{out_path}' hint='pass --force to overwrite'")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(text, encoding="utf-8")
    log_info(f"wrote | path='{out_path}'")


def remove_stale_rows(base, expected, force):
    """Drop rows files an earlier run left for a community this run no longer writes; they would fail the checker."""
    stale = sorted(path for path in base.glob("*.json") if path.name not in expected)
    if not stale:
        return
    if not force:
        die(f"stale rows files from an earlier run | paths='{', '.join(str(p) for p in stale)}' hint='pass --force to remove them'")
    for path in stale:
        path.unlink()
        log_info(f"removed stale | path='{path}'")


def write_rows_dir(rows_dir, universal_rows, clusters_out, force):
    """glossary.json = universal rows; <slug>.json = universal rows then the article's rows, both in table order."""
    base = Path(rows_dir)
    articles = [cluster for cluster in clusters_out if cluster["rows"]]
    if base.is_dir():
        remove_stale_rows(base, {"glossary.json", *(f"{cluster['slug']}.json" for cluster in articles)}, force)
    write_text(base / "glossary.json", json.dumps({"rows": universal_rows}, indent=1, ensure_ascii=False) + "\n", force)
    for cluster in articles:
        body = {"rows": universal_rows + cluster["rows"]}
        write_text(base / f"{cluster['slug']}.json", json.dumps(body, indent=1, ensure_ascii=False) + "\n", force)


def parse_args():
    parser = argparse.ArgumentParser(description="Cluster a discover graph into subsystems and split the refined table into glossary and article rows.")
    parser.add_argument("--discover", required=True, help="discover-pass JSON ({definitions:[{term, depends_on, ...}]})")
    parser.add_argument("--refined", help="accepted definitions table JSON ({rows:[{term, definition, doc_url}]}) in table order")
    parser.add_argument("--alias", action="append", default=[], help='"REFINED TERM=DISCOVER TERM" for rows the refine pass renamed (repeatable)')
    parser.add_argument("--merge", action="append", default=[], help='"COMMUNITY=INTO": fold one community into another, each by current name, slug, or a name it absorbed (repeatable)')
    parser.add_argument("--rename", action="append", default=[], help='"COMMUNITY=NEW NAME": rename a community and its slug; its core list is unchanged (repeatable)')
    parser.add_argument("--universal", action="append", default=[], help='"TERM": force this accepted-table row into the glossary before the closure runs, for a term the articles share (repeatable)')
    parser.add_argument("--out", help="write the clusters JSON here instead of stdout")
    parser.add_argument("--mermaid", help="write the cluster-level flowchart (.mmd) here")
    parser.add_argument("--rows-dir", dest="rows_dir", help="write glossary.json and one <slug>.json per article here, for check_definitions_order")
    parser.add_argument("--min-size", dest="min_size", type=int, default=0, help="community floor before merging (default: 2%% of nodes, at least 3)")
    parser.add_argument("--min-rows", dest="min_rows", type=int, default=DEFAULT_MIN_ROWS, help="fold a community with fewer than N hoisted rows into its most-connected neighbour (default 0: never; an article may hoist no rows)")
    parser.add_argument("--universal-floor", dest="universal_floor", type=int, default=0, help="dependents a row needs to be universal (default: nodes/15, at least 3)")
    parser.add_argument("--universal-ratio", dest="universal_ratio", type=float, default=DEFAULT_UNIVERSAL_RATIO, help="share of dependents outside the row's community (default 0.5)")
    parser.add_argument("--force", action="store_true", help="overwrite existing output files")
    return parser.parse_args()


def build_clusters_out(state, names, rows, assignments):
    clusters_out = []
    for ci, members in enumerate(state.clusters):
        ranked = rank_members(state.deps, members)
        sections = []
        parts = split_sections(state.adj, members)
        if len(parts) > 1:
            for part in sorted(parts, key=lambda p: (-len(p), p[0])):
                part_ranked = rank_members(state.deps, part)
                sections.append({"name": state.terms[part_ranked[0]]["term"], "core": [state.terms[j]["term"] for j in part_ranked[:CORE_SIZE]], "terms": [state.terms[j]["term"] for j in part_ranked]})
        hoisted = [row for row, a in zip(rows, assignments) if a["cluster"] == ci and not a["universal"]]
        universal_here = [row["term"] for row, a in zip(rows, assignments) if a["cluster"] == ci and a["universal"]]
        clusters_out.append({
            "id": ci,
            "name": names[ci],
            "slug": slugify(names[ci]),
            "core": [state.terms[j]["term"] for j in ranked[:CORE_SIZE]],
            "merged_from": state.former_names(ci),
            "size": len(members),
            "terms": [state.terms[j]["term"] for j in ranked],
            "sections": sections,
            "rows": hoisted,
            "universal_rows": universal_here,
        })
    return clusters_out


def check_universal_share(universal_count, row_count):
    if row_count == 0:
        return
    share = universal_count / row_count
    low, high = EXPECTED_UNIVERSAL_SHARE
    if share < low:
        log_warn(f"few universal rows: clusters may be too coarse | share='{share:.2f}' expected='{low}-{high}'")
        return
    if share > high:
        log_warn(f"many universal rows: clusters may be too fine | share='{share:.2f}' expected='{low}-{high}'")
        return
    log_info(f"universal share in range | share='{share:.2f}' expected='{low}-{high}'")


def main():
    args = parse_args()
    if not 0 < args.universal_ratio <= 1:
        die(f"invalid --universal-ratio | universal_ratio='{args.universal_ratio}' expected='(0, 1]'")
    if args.min_size < 0 or args.universal_floor < 0 or args.min_rows < 0:
        die(f"negative size | min_size='{args.min_size}' universal_floor='{args.universal_floor}' min_rows='{args.min_rows}' expected='>= 0'")
    merges = parse_pairs(args.merge, "--merge", "COMMUNITY=INTO")
    renames = parse_pairs(args.rename, "--rename", "COMMUNITY=NEW NAME")

    terms = load_terms(args.discover)
    deps, adj = build_graph(terms)
    node_count = len(terms)
    active = [i for i in range(node_count) if adj[i]]
    isolated = [terms[i]["term"] for i in range(node_count) if not adj[i]]
    min_size = args.min_size or max(3, round(node_count * TINY_FRACTION))
    floor = args.universal_floor or max(3, round(node_count / UNIVERSAL_FLOOR_DIVISOR))

    top = greedy_modularity(induced(adj, active))
    state = Communities(terms, deps, adj, [[active[k] for k in part] for part in top])
    merge_small(state, min_size)
    state.sort()
    log_info(f"communities | count='{len(state.clusters)}' sizes='{[len(m) for m in state.clusters]}' modularity='{modularity(adj, state.clusters):.3f}' min_size='{min_size}' isolated='{len(isolated)}'")

    rows = load_rows(args.refined) if args.refined else []
    nodes = map_rows(rows, terms, parse_aliases(args.alias)) if rows else []
    forced = resolve_rows(rows, args.universal) if rows else []
    apply_user_merges(state, merges)
    assignments, promoted = assign_and_merge_thin(state, rows, nodes, forced, args.universal_ratio, floor, args.min_rows)
    names = apply_renames(state, renames)
    for record in promoted:
        log_info(f"promoted | term='{record['term']}' because_of='{record['because_of']}'")
    q = modularity(adj, state.clusters)
    if state.merged:
        log_info(f"partition after merges | count='{len(state.clusters)}' sizes='{[len(m) for m in state.clusters]}' modularity='{q:.3f}' merged='{len(state.merged)}'")

    clusters_out = build_clusters_out(state, names, rows, assignments)
    cluster_of = state.cluster_of()
    counts = dependents_by_cluster(deps, cluster_of)
    universal_rows = [row for row, a in zip(rows, assignments) if a["universal"]]
    unmapped = [row["term"] for row, a in zip(rows, assignments) if a["reason"] == "unmapped"]
    check_universal_share(len(universal_rows), len(rows))
    cross = cross_article_mentions(rows, assignments, names)
    for cluster in clusters_out:
        log_info(f"cluster | id='{cluster['id']}' name='{cluster['name']}' core='{' / '.join(cluster['core'])}' size='{cluster['size']}' rows='{len(cluster['rows'])}' sections='{len(cluster['sections'])}'")
    if rows:
        log_info(f"glossary | universal='{len(universal_rows)}' of='{len(rows)}' forced='{len(forced)}' promoted='{len(promoted)}' unmapped='{len(unmapped)}' floor='{floor}' ratio='{args.universal_ratio}' min_rows='{args.min_rows}'")

    edges, threshold = cluster_edges(deps, cluster_of, len(state.clusters))
    glossary_order = sorted(
        [(row, node) for row, node, a in zip(rows, nodes, assignments) if a["universal"] and node is not None],
        key=lambda pair: -sum(counts[pair[1]].values()),
    )
    result = {
        "parameters": {"min_size": min_size, "min_rows": args.min_rows, "universal_floor": floor, "universal_ratio": args.universal_ratio},
        "nodes": node_count,
        "modularity": round(q, 4),
        "clusters": clusters_out,
        "universal": [row["term"] for row in universal_rows],
        "forced_universal": [rows[i]["term"] for i in forced],
        "promoted": promoted,
        "merged": state.merged,
        "cross_article_mentions": cross,
        "unmapped": unmapped,
        "isolated": isolated,
        "cross_edges": [[ci, cj, w] for ci, cj, w in edges],
        "cross_edge_threshold": threshold,
    }
    text = json.dumps(result, indent=1, ensure_ascii=False) + "\n"
    if args.mermaid:
        write_text(args.mermaid, cluster_mermaid(clusters_out, edges, threshold, [row["term"] for row, _ in glossary_order]), args.force)
    if args.rows_dir:
        write_rows_dir(args.rows_dir, universal_rows, clusters_out, args.force)
    if not args.out:
        print(text, end="")
        return
    write_text(args.out, text, args.force)
    print(str(Path(args.out)))


if __name__ == "__main__":
    main()
