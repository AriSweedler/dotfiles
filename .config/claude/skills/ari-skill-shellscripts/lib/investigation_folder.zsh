#!/usr/bin/env zsh
# Canonical investigation-folder helper for skill zsh scripts. Source it; do not execute.
#
#   source "${SKILLS_DIR}/ari-skill-shellscripts/lib/investigation_folder.zsh"
#   dir="$(mk_investigation_dir /tmp/skill-update "${skill}")"

#######
# Create a fresh timestamped investigation folder at <root>/<skill>/<ts> and print
# its path. The timestamp is UTC (YYYYMMDDThhmmssZ) so concurrent sessions never
# clash. Logging is left to the caller — this helper stays dependency-free.
# Arguments:
#   $1 = root (e.g. /tmp/skill-update)
#   $2 = skill name
# Outputs: the created directory path on stdout
#######
mk_investigation_dir() {
    local root="${1}" skill="${2}"
    local ts dir
    ts="$(date -u '+%Y%m%dT%H%M%SZ')"
    dir="${root}/${skill}/${ts}"
    mkdir -p "${dir}"
    echo "${dir}"
}
