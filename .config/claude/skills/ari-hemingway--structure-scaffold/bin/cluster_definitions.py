#!/usr/bin/env python3
"""Cluster a scaffold's discover graph into subsystems and split the refined table.
Run: zsh $HOME/.claude/skills/ari-hemingway--structure-scaffold/bin/cluster_definitions.zsh --help

Graph: every discover term is a node; each entry in a term's depends_on list is a directed
edge term -> dependency. Communities: greedy modularity (Clauset-Newman-Moore) on the
undirected graph, stopped at the modularity peak, ties broken by row order. Each community
is re-clustered once on its induced subgraph to propose headings inside its article.
Communities under the size floor merge into the neighbour they share the most edges with.
Refined rows inherit their discover term's community. A row is universal when at least
--universal-ratio of its dependents sit outside its community and it has at least
--universal-floor dependents; universal rows form the glossary, the rest hoist into articles.
"""
import argparse
import json
import re
from collections import Counter
from pathlib import Path

from at_log import log_info, log_warn, die

DEFAULT_UNIVERSAL_RATIO = 0.5
UNIVERSAL_FLOOR_DIVISOR = 15  # floor = nodes / 15: about 20 dependents on a 300-node graph
TINY_FRACTION = 0.02  # communities under 2% of the nodes merge into a neighbour
MIN_SECTION_SPLIT = 12  # communities smaller than this get no section split
MIN_SECTION_SIZE = 2  # sections smaller than this merge into a sibling section
CLUSTER_EDGES_PER_NODE = 2  # cluster-diagram edges kept: about this many per community
CORE_SIZE = 3  # name candidates shown per community
GLOSSARY_PREVIEW = 10  # universal terms drawn in the cluster diagram
EXPECTED_UNIVERSAL_SHARE = (0.15, 0.5)  # outside this share the clustering is off


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


def merge_tiny(adj, clusters, min_size):
    """Merge every community under min_size into the community it shares the most edges with."""
    clusters = [list(members) for members in clusters]
    while len(clusters) > 1:
        cluster_of = {v: ci for ci, members in enumerate(clusters) for v in members}
        tiny = [ci for ci, members in enumerate(clusters) if len(members) < min_size]
        if not tiny:
            break
        ci = min(tiny, key=lambda k: (len(clusters[k]), k))
        weights = Counter()
        for v in clusters[ci]:
            for u, w in adj[v].items():
                target = cluster_of.get(u)
                if target is not None and target != ci:
                    weights[target] += w
        target = choose_merge_target(weights, ci, len(clusters))
        clusters[target].extend(clusters[ci])
        del clusters[ci]
    return [sorted(members) for members in clusters]


def choose_merge_target(weights, ci, count):
    if weights:
        return max(sorted(weights), key=lambda k: weights[k])
    return min(k for k in range(count) if k != ci)


def rank_members(deps, members):
    """Members by in-degree from cluster-mates, highest first; ties by row order."""
    inside = set(members)
    in_degree = Counter()
    for i in members:
        for j in deps[i]:
            if j in inside:
                in_degree[j] += 1
    return sorted(members, key=lambda j: (-in_degree[j], j))


def split_sections(adj, members):
    if len(members) < MIN_SECTION_SPLIT:
        return [members]
    parts = greedy_modularity(induced(adj, members))
    if len(parts) < 2:
        return [members]
    sections = [sorted(members[k] for k in part) for part in parts]
    return merge_tiny(adj, sections, MIN_SECTION_SIZE)


def parse_aliases(pairs):
    aliases = {}
    for pair in pairs:
        if "=" not in pair:
            die(f"invalid alias | alias='{pair}' expected='REFINED TERM=DISCOVER TERM'")
        left, right = pair.split("=", 1)
        aliases[norm(left)] = right
    return aliases


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


def write_rows_dir(rows_dir, universal_rows, clusters_out, force):
    """glossary.json = universal rows; <slug>.json = universal rows then the article's rows, both in table order."""
    base = Path(rows_dir)
    write_text(base / "glossary.json", json.dumps({"rows": universal_rows}, indent=1, ensure_ascii=False) + "\n", force)
    for cluster in clusters_out:
        if not cluster["rows"]:
            continue
        body = {"rows": universal_rows + cluster["rows"]}
        write_text(base / f"{cluster['slug']}.json", json.dumps(body, indent=1, ensure_ascii=False) + "\n", force)


def parse_args():
    parser = argparse.ArgumentParser(description="Cluster a discover graph into subsystems and split the refined table into glossary and article rows.")
    parser.add_argument("--discover", required=True, help="discover-pass JSON ({definitions:[{term, depends_on, ...}]})")
    parser.add_argument("--refined", help="accepted definitions table JSON ({rows:[{term, definition, doc_url}]}) in table order")
    parser.add_argument("--alias", action="append", default=[], help='"REFINED TERM=DISCOVER TERM" for rows the refine pass renamed (repeatable)')
    parser.add_argument("--out", help="write the clusters JSON here instead of stdout")
    parser.add_argument("--mermaid", help="write the cluster-level flowchart (.mmd) here")
    parser.add_argument("--rows-dir", dest="rows_dir", help="write glossary.json and one <slug>.json per article here, for check_definitions_order")
    parser.add_argument("--min-size", dest="min_size", type=int, default=0, help="community floor before merging (default: 2%% of nodes, at least 3)")
    parser.add_argument("--universal-floor", dest="universal_floor", type=int, default=0, help="dependents a row needs to be universal (default: nodes/15, at least 3)")
    parser.add_argument("--universal-ratio", dest="universal_ratio", type=float, default=DEFAULT_UNIVERSAL_RATIO, help="share of dependents outside the row's community (default 0.5)")
    parser.add_argument("--force", action="store_true", help="overwrite existing output files")
    return parser.parse_args()


def assign_rows(rows, nodes, cluster_of, counts, ratio, floor):
    """Per row: (cluster id or None, universal flag, reason)."""
    assignments = []
    for row, node in zip(rows, nodes):
        if node is None:
            assignments.append((None, True, "unmapped"))
            continue
        cluster = cluster_of.get(node)
        if cluster is None:
            assignments.append((None, True, "isolated"))
            continue
        assignments.append((cluster, is_universal(counts, node, cluster, ratio, floor), "graph"))
    return assignments


def build_clusters_out(terms, deps, adj, clusters, rows, assignments):
    clusters_out = []
    for ci, members in enumerate(clusters):
        ranked = rank_members(deps, members)
        name = terms[ranked[0]]["term"]
        sections = []
        parts = split_sections(adj, members)
        if len(parts) > 1:
            for part in sorted(parts, key=lambda p: (-len(p), p[0])):
                part_ranked = rank_members(deps, part)
                sections.append({"name": terms[part_ranked[0]]["term"], "core": [terms[j]["term"] for j in part_ranked[:CORE_SIZE]], "terms": [terms[j]["term"] for j in part_ranked]})
        hoisted = [row for row, (cluster, universal, _) in zip(rows, assignments) if cluster == ci and not universal]
        universal_here = [row["term"] for row, (cluster, universal, _) in zip(rows, assignments) if cluster == ci and universal]
        clusters_out.append({
            "id": ci,
            "name": name,
            "slug": slugify(name),
            "core": [terms[j]["term"] for j in ranked[:CORE_SIZE]],
            "size": len(members),
            "terms": [terms[j]["term"] for j in ranked],
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
    if args.min_size < 0 or args.universal_floor < 0:
        die(f"negative size | min_size='{args.min_size}' universal_floor='{args.universal_floor}' expected='>= 0'")

    terms = load_terms(args.discover)
    deps, adj = build_graph(terms)
    node_count = len(terms)
    active = [i for i in range(node_count) if adj[i]]
    isolated = [terms[i]["term"] for i in range(node_count) if not adj[i]]
    min_size = args.min_size or max(3, round(node_count * TINY_FRACTION))
    floor = args.universal_floor or max(3, round(node_count / UNIVERSAL_FLOOR_DIVISOR))

    top = greedy_modularity(induced(adj, active))
    clusters = merge_tiny(adj, [sorted(active[k] for k in part) for part in top], min_size)
    clusters.sort(key=lambda members: (-len(members), members[0]))
    q = modularity(adj, clusters)
    log_info(f"communities | count='{len(clusters)}' sizes='{[len(m) for m in clusters]}' modularity='{q:.3f}' min_size='{min_size}' isolated='{len(isolated)}'")

    cluster_of = {v: ci for ci, members in enumerate(clusters) for v in members}
    rows = load_rows(args.refined) if args.refined else []
    nodes = map_rows(rows, terms, parse_aliases(args.alias)) if rows else []
    counts = dependents_by_cluster(deps, cluster_of)
    assignments = assign_rows(rows, nodes, cluster_of, counts, args.universal_ratio, floor)
    clusters_out = build_clusters_out(terms, deps, adj, clusters, rows, assignments)

    universal_rows = [row for row, (_, universal, _) in zip(rows, assignments) if universal]
    unmapped = [row["term"] for row, (_, _, reason) in zip(rows, assignments) if reason == "unmapped"]
    check_universal_share(len(universal_rows), len(rows))
    for cluster in clusters_out:
        log_info(f"cluster | id='{cluster['id']}' name='{cluster['name']}' core='{' / '.join(cluster['core'])}' size='{cluster['size']}' rows='{len(cluster['rows'])}' sections='{len(cluster['sections'])}'")
    if rows:
        log_info(f"glossary | universal='{len(universal_rows)}' of='{len(rows)}' unmapped='{len(unmapped)}' floor='{floor}' ratio='{args.universal_ratio}'")

    edges, threshold = cluster_edges(deps, cluster_of, len(clusters))
    glossary_order = sorted(
        [(row, node) for row, node, (_, universal, _) in zip(rows, nodes, assignments) if universal and node is not None],
        key=lambda pair: -sum(counts[pair[1]].values()),
    )
    result = {
        "parameters": {"min_size": min_size, "universal_floor": floor, "universal_ratio": args.universal_ratio},
        "nodes": node_count,
        "modularity": round(q, 4),
        "clusters": clusters_out,
        "universal": [row["term"] for row in universal_rows],
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
