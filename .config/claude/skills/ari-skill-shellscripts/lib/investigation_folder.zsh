#!/usr/bin/env zsh
# Canonical investigation-folder helper for skill zsh scripts. Source it; do not execute.
#
#   source "${SKILLS_DIR}/ari-skill-shellscripts/lib/investigation_folder.zsh"
#   dir="$(mk_investigation_dir /tmp/skill-update "${skill}")" || exit 1

#######
# Create a fresh timestamped investigation folder at <root>/<skill>/<ts> and print
# its path. The timestamp is UTC (YYYYMMDDThhmmssZ). A call whose <ts> folder
# exists gets <ts>-2, then <ts>-3, so no two calls share a folder, within one
# process, across processes, or when a caller made <ts> by hand. Callers treat
# the leaf as opaque. Logging is left to the caller: on failure the helper prints
# one [ERROR] line to stderr and returns 1.
# Arguments:
#   $1 = root (e.g. /tmp/skill-update)
#   $2 = skill name
# Outputs: the created directory path on stdout
#######
mk_investigation_dir() {
    local root="${1}" skill="${2}"
    local ts parent dir
    local -i n=1
    ts="$(date -u '+%Y%m%dT%H%M%SZ')" && [[ -n "${ts}" ]] || {
        print -u2 "[ERROR] date failed"
        return 1
    }
    parent="${root}/${skill}"
    mkdir -p "${parent}" || {
        print -u2 "[ERROR] cannot create parent | parent='${parent}'"
        return 1
    }
    dir="${parent}/${ts}"
    # Plain mkdir, never -p: it fails on an existing leaf, which is the collision signal.
    until mkdir "${dir}" 2>/dev/null; do
        if [[ ! -d "${dir}" ]]; then
            print -u2 "[ERROR] cannot create investigation folder | dir='${dir}'"
            return 1
        fi
        (( n += 1 ))
        dir="${parent}/${ts}-${n}"
    done
    print -r -- "${dir}"
}
