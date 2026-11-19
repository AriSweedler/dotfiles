#!/usr/bin/env zsh
#
# bead-links.zsh — print one card link per bead id, for the OpenCode footer slot and
# its picker to render as clickable text.
#
# Everything about the card — the fields, the colors from beads.conf, the copy text,
# the URL itself — is built by bead_link.zsh (ari-bead-driven-development), never here.
# This script only does what bead_link cannot: read the beads' titles, statuses and
# priorities from bd, and cache the result.
#
# Two calls, whatever the number of ids:
#   - bead_link with the real config, no --card  → each bead's Scotty page (https),
#     which is what a click in OpenCode can open.
#   - bead_link with a scotty-less copy of the config and --card → the tmux-only
#     tmux-tooltip:// link, because --card emits the https form whenever the workspace
#     has a scotty line, and the tmux form is what pops the card and copies.
# Dropping only the scotty lines keeps every color rule, so the card is colored
# exactly as Claude's is.
#
# Cached, because bd is slow and this runs on every turn end: `bd show` costs ~0.39s
# for one bead and ~0.25s for each one after it. A row younger than CACHE_TTL is
# printed from the cache and costs one python startup; only misses reach bd.
#
# Usage: bead-links.zsh [--workspace DIR] <bead-id>...
# Output: one `<id>\t<card-url>\t<page-url>\t<title>` line per id bd knows, in input order.

set -u

readonly BEAD_LINK="${HOME}/.claude/skills/ari-bead-driven-development/bin/bead_link.zsh"
readonly BEADS_CONF="${HOME}/.config/tmux-tooltip/beads.conf"
readonly CACHE="${TMPDIR:-/tmp}/opencode-bead-cards.tsv"
readonly CACHE_TTL=300
# Machines that must never emit Scotty links: on a machine that cannot reach Scotty a link
# there is a dead end, and the footer would offer a click that goes nowhere. A machine whose
# everyday name ends in -work (dotfiles machine-name) is one; BEAD_LINKS_NO_SCOTTY forces the
# same anywhere. No host is named here: this tier is public.
readonly NO_SCOTTY_SUFFIX="-work"
BD="$(command -v bd || print -r -- /etc/profiles/per-user/${USER:-$(id -un)}/bin/bd)"

#######################################
# Prints 1 when this machine must not get Scotty links, else 0. The everyday name is the one
# dotfiles keeps (`dotfiles machine-name`, a local-tier file), not the hostname: on a managed
# machine those differ, and a hostname like LP7HQH57GF says nothing.
#######################################
no_scotty() {
  [[ -n "${BEAD_LINKS_NO_SCOTTY:-}" ]] && { print -r -- 1; return 0; }
  local name=""
  [[ -x "${HOME}/.config/bin/dotfiles" ]] && name="$("${HOME}/.config/bin/dotfiles" machine-name 2>/dev/null)"
  [[ -n "${name}" ]] || name="$(hostname -s 2>/dev/null)"
  [[ "${(L)name}" == *"${NO_SCOTTY_SUFFIX}" ]] && print -r -- 1 || print -r -- 0
}

main() {
  local workspace="${HOME}/beads"
  while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --workspace) workspace="$2"; shift 2 ;;
      *) print -u2 -r -- "bead-links: unknown flag '$1'"; return 64 ;;
    esac
  done
  (( $# )) || return 0

  python3 - "${BD}" "${workspace}" "${BEAD_LINK}" "${BEADS_CONF}" "${CACHE}" "${CACHE_TTL}" "$(no_scotty)" "$@" <<'PY'
import json, os, re, subprocess, sys, time

bd, workspace, bead_link, conf_path, cache_path, ttl, no_scotty = sys.argv[1:8]
ttl = int(ttl)
no_scotty = no_scotty == "1"
ids = sys.argv[8:]

# id -> (card, page, title, epoch)
cache = {}
try:
    with open(cache_path) as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 5:
                cache[parts[0]] = (parts[1], parts[2], parts[3], float(parts[4]))
except FileNotFoundError:
    pass

now = time.time()
rows, missing = {}, []
for bead_id in ids:
    row = cache.get(bead_id)
    if row and now - row[3] < ttl:
        # An empty card is a cached miss: bd does not know this id (a phantom id
        # quoted in the transcript, say), so do not ask bd about it again until the
        # row expires. Without this, every turn pays a bd read for the same phantoms.
        if row[0]:
            rows[bead_id] = row[:3]
    else:
        missing.append(bead_id)

def definitions(out):
    found = {}
    for line in out.splitlines():
        m = re.match(r"^\[([^\]]+)\]:\s*(\S+)\s*$", line)
        if m:
            found[m.group(1)] = m.group(2)
    return found

if missing:
    beads = {}
    out = subprocess.run([bd, "-C", workspace, "show", *missing, "--json"],
                         capture_output=True, text=True)
    if out.returncode == 0 and out.stdout.strip():
        try:
            beads = {b["id"]: b for b in json.loads(out.stdout)}
        except json.JSONDecodeError:
            beads = {}
    known = [bead_id for bead_id in missing if bead_id in beads]

    if known:
        # The real config: the Scotty page, which is the URL a click can open. Skipped
        # entirely on a machine that must not link to Scotty.
        pages = {}
        if not no_scotty:
            pages = definitions(subprocess.run(
                ["/bin/zsh", bead_link, "--here"] + [arg for bead_id in known for arg in ("--bead", bead_id)],
                capture_output=True, text=True).stdout)

        # A scotty-less copy of the same config: every color rule, no page URL, so
        # --card yields the tmux-only link.
        try:
            with open(conf_path) as handle:
                lines = handle.read().splitlines()
        except FileNotFoundError:
            lines = []
        noscotty = cache_path + ".conf"
        with open(noscotty, "w") as handle:
            handle.write("\n".join(l for l in lines if not re.match(r"^\s*scotty\b", l)) + "\n")

        card_args = ["/bin/zsh", bead_link, "--here", "--card"]
        for bead_id in known:
            bead = beads[bead_id]
            card_args += ["--bead", bead_id,
                          "--title", bead.get("title") or bead_id,
                          "--status", bead.get("status") or "open",
                          "--priority", str(bead.get("priority", 2))]
        cards = definitions(subprocess.run(
            card_args, capture_output=True, text=True,
            env={**os.environ, "BEAD_LINK_CONFIG": noscotty}).stdout)

        for bead_id in known:
            card = cards.get(bead_id)
            if not card:
                continue
            # No page URL means no click target: the plugin renders the id as plain
            # text rather than a link that cannot go anywhere.
            page = pages.get(bead_id, "")
            title = beads[bead_id].get("title") or bead_id
            cache[bead_id] = (card, page, title, now)
            rows[bead_id] = (card, page, title)

        # Remember the ids bd does not know, so they cost nothing until they expire.
        for bead_id in missing:
            if bead_id not in beads:
                cache[bead_id] = ("", "", "", now)

        # Rewrite with everything still inside the window, so the file cannot grow
        # without bound as ids come and go.
        keep = {k: v for k, v in cache.items() if now - v[3] < ttl * 4}
        try:
            with open(cache_path, "w") as handle:
                for bead_id, (card, page, title, epoch) in keep.items():
                    handle.write("\t".join([bead_id, card, page, title, repr(epoch)]) + "\n")
        except OSError:
            pass

for bead_id in ids:
    row = rows.get(bead_id)
    if row:
        print("\t".join((bead_id,) + row))
PY
}

main "$@"
