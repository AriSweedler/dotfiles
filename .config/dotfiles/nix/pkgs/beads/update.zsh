#!/usr/bin/env zsh
# Bumps pkgs/beads/default.nix to an upstream bd release: the version, and every asset hash from
# that release's checksums.txt, then builds the result for this system and runs its bd --version.
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/dry_run.zsh"

readonly SCRIPT_PATH="${0:a}"
readonly REPO="gastownhall/beads"
readonly RELEASES_URL="https://github.com/${REPO}/releases/download"
readonly LATEST_API_URL="https://api.github.com/repos/${REPO}/releases/latest"
readonly CURL_MAX_TIME=30
readonly REVIEW_SKILLS_DIR="${BEADS_UPDATE_SKILLS_DIR:-${SKILLS_DIR}}"

help() {
  cat <<EOF
${c_green}update.zsh${c_rst} — bump the beads (bd) package to an upstream release

Reads the release's checksums.txt, turns each asset digest default.nix names into an SRI hash,
rewrites version and hashes, then builds the rewritten package for this system and checks its
bd --version. A dry run unless --execute: the build runs either way, the file is written only
with --execute. Never switches: \`dotfiles switch\` stays a separate step.

${c_bold}Usage:${c_rst}
  zsh $HOME/dotfiles/.config/dotfiles/nix/pkgs/beads/update.zsh [--version V] [--execute]

${c_bold}Options:${c_rst}
  ${c_cyan}--version V${c_rst}   Release to pin, as 1.3.4 or v1.3.4 (default: the latest, from the GitHub API)
  ${c_cyan}--file F${c_rst}      Package file to rewrite (default: default.nix beside this script)
  ${c_cyan}--flake DIR${c_rst}   Flake whose nixpkgs builds the package (default: the nix dir above pkgs/)
  ${c_cyan}--no-build${c_rst}    Skip the build and the bd --version check
  ${c_cyan}--execute${c_rst}     Write the file
  ${c_cyan}--dry-run${c_rst}     Preview only (the default; wins over --execute)
  ${c_cyan}-h, --help${c_rst}    Show this help

${c_bold}Output:${c_rst}
  hash_<platform>=<sri>   one line per asset
  old_version, version, file, changed=0|1, out_path, bd_version
  skill_review=<skills naming the old version, comma-separated; empty when the version is unchanged>
  dry_run=1|0, changes=N
EOF
}

#######################################
# Print the latest release's version, without its leading v.
# Arguments: None
# Returns: 1 when the API call fails or names no tag
#######################################
latest_version() {
  local tag
  tag="$(curl -fsSL --max-time "${CURL_MAX_TIME}" "${LATEST_API_URL}" | jq -r '.tag_name // empty')"
  if [[ -z "${tag}" ]]; then
    log::err "No tag_name in the latest-release answer | url='${LATEST_API_URL}'"
    return 1
  fi
  log::info "Latest upstream release | tag='${tag}'"
  print -r -- "${tag#v}"
}

#######################################
# Print the version argument, or the latest release when none was given.
# Arguments: $1 - the --version value, possibly empty
#######################################
choose_version() {
  local wanted="${1}"
  if [[ -n "${wanted}" ]]; then
    log::info "Using the version given | version='${wanted#v}'"
    print -r -- "${wanted#v}"
    return
  fi
  log::info "No --version; asking GitHub for the latest release | url='${LATEST_API_URL}'"
  latest_version
}

#######################################
# Print each "platform = ..." value default.nix names, one per line.
# Arguments: $1 - default.nix
#######################################
nix_platforms() {
  awk 'match($0, /platform = "[^"]+"/) { print substr($0, RSTART + 12, RLENGTH - 13) }' "${1}"
}

#######################################
# Print the version default.nix pins.
# Arguments: $1 - default.nix
#######################################
nix_version() {
  awk 'match($0, /^ *version = "[^"]+";/) { s = substr($0, RSTART, RLENGTH); sub(/^ *version = "/, "", s); sub(/";$/, "", s); print s }' "${1}"
}

#######################################
# Print default.nix with the version and each platform's hash replaced.
# Arguments: $1 - default.nix; $2 - version; then platform=sri pairs
# Returns: 1 when the version line or a platform's hash line is not found exactly once
#######################################
rewrite_nix() {
  local file="${1}" version="${2}"
  shift 2
  print -l -- "$@" | awk -v version="${version}" -v expected="$#" '
    FNR == NR { split($0, kv, "="); sri[kv[1]] = substr($0, length(kv[1]) + 2); next }
    /^ *version = "[^"]+";/ { sub(/"[^"]+"/, "\"" version "\""); versions++ }
    match($0, /platform = "[^"]+"/) {
      p = substr($0, RSTART + 12, RLENGTH - 13)
      if ((p in sri) && sub(/hash = "[^"]+"/, "hash = \"" sri[p] "\"")) { hashed++ }
    }
    { print }
    END {
      if (versions != 1) { print "version lines: " versions > "/dev/stderr"; exit 1 }
      if (hashed != expected) { print "hash lines: " hashed " of " expected > "/dev/stderr"; exit 1 }
    }
  ' - "${file}"
}

#######################################
# Build a package file with the flake's nixpkgs and print its store path.
# Arguments: $1 - the package file; $2 - the flake directory
#######################################
build_package() {
  local file="${1}" flake="${2}"
  nix build --impure --no-link --print-out-paths --expr \
    "(builtins.getFlake \"path:${flake}\").inputs.nixpkgs.legacyPackages.\${builtins.currentSystem}.callPackage (/. + \"${file}\") { }"
}

#######################################
# Print the skills whose SKILL.md names the old bd version, comma-separated, when it changes.
# Arguments: $1 - old version; $2 - new version
#######################################
skills_to_review() {
  local old="${1}" new="${2}"
  if [[ "${old}" == "${new}" ]]; then
    log::info "Version unchanged; no skill review | version='${new}'"
    return
  fi
  local -a hits=("${REVIEW_SKILLS_DIR}"/*/SKILL.md(N))
  hits=(${(f)"$(grep -lF -- "${old}" "${hits[@]}" /dev/null || true)"})
  hits=(${hits:h:t})
  local found="${(j:,:)hits}"
  if [[ -n "${found}" ]]; then
    log::warn "These skills are written against the old bd; review them after the switch | old='${old}' new='${new}' skills='${found}'"
  fi
  print -r -- "${found}"
}

main() {
  local -a args=("${@}")
  local execute=false dry_run=false build=true wanted="" file="${SCRIPT_DIR}/default.nix" flake=""
  while (( $# > 0 )); do
    case "${1}" in
      -h|--help) help; exit 0 ;;
      --version) wanted="${2:?--version requires a value}"; shift 2 ;;
      --file) file="${2:?--file requires a value}"; shift 2 ;;
      --flake) flake="${2:?--flake requires a value}"; shift 2 ;;
      --no-build) build=false; shift ;;
      --execute) execute=true; shift ;;
      --dry-run) dry_run=true; shift ;;
      *) log::err "Unknown flag | flag='${1}'"; help; exit 1 ;;
    esac
  done
  resolve_dry_run "${execute}" "${dry_run}"

  file="${file:A}"
  [[ -n "${flake}" ]] || flake="${file:h:h:h}"
  flake="${flake:A}"

  local -a missing=()
  local tool
  for tool in curl jq nix awk diff; do
    command -v "${tool}" >/dev/null || missing+=("${tool}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing prerequisites | missing='${(j:, :)missing}'"
    exit 1
  fi
  if [[ ! -r "${file}" ]]; then
    log::err "Package file not readable | file='${file}'"
    exit 1
  fi
  if [[ "${build}" == true && ! -r "${flake}/flake.nix" ]]; then
    log::err "No flake.nix in the flake dir | flake='${flake}'"
    exit 1
  fi

  local version
  version="$(choose_version "${wanted}")"
  if [[ ! "${version}" =~ '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$' ]]; then
    log::err "Not a release version | version='${version}' expected='MAJOR.MINOR.PATCH, optional v prefix'"
    exit 1
  fi
  local old_version
  old_version="$(nix_version "${file}")"

  local url="${RELEASES_URL}/v${version}/checksums.txt" checksums
  log::info "Fetching checksums | url='${url}'"
  if ! checksums="$(curl -fsSL --max-time "${CURL_MAX_TIME}" "${url}")"; then
    log::err "No checksums.txt for this release; is the version right? | version='${version}' url='${url}'"
    exit 1
  fi

  local -a platforms=(${(f)"$(nix_platforms "${file}")"}) pairs=()
  if (( ${#platforms} == 0 )); then
    log::err "No platform entries in the package file | file='${file}'"
    exit 1
  fi
  local platform asset hex sri
  for platform in "${platforms[@]}"; do
    asset="beads_${version}_${platform}.tar.gz"
    hex="$(print -r -- "${checksums}" | awk -v a="${asset}" '$2 == a { print $1 }')"
    if [[ ! "${hex}" =~ '^[0-9a-f]{64}$' ]]; then
      log::err "checksums.txt has no sha256 for an asset the package needs | asset='${asset}' hex='${hex}' url='${url}'"
      exit 1
    fi
    sri="$(nix hash convert --hash-algo sha256 --to sri "${hex}")"
    log::info "Asset hash | platform='${platform}' hex='${hex}' sri='${sri}'"
    pairs+=("${platform}=${sri}")
  done

  local scratch candidate
  scratch="$(mktemp -d "${${TMPDIR:-/tmp}%/}/beads-update.XXXXXX")"
  trap "rm -rf '${scratch}'" EXIT
  candidate="${scratch}/default.nix"
  if ! rewrite_nix "${file}" "${version}" "${pairs[@]}" > "${candidate}"; then
    log::err "Package file does not have the expected shape; nothing written | file='${file}'"
    exit 1
  fi

  local changed=0
  if ! cmp -s "${file}" "${candidate}"; then
    changed=1
    log::INFO "$(diff -u "${file}" "${candidate}" || true)"
  fi
  if (( changed == 0 )); then
    log::info "The pinned version and hashes already match upstream | version='${version}' file='${file}'"
  fi

  local out_path="" bd_version=""
  if [[ "${build}" == true ]]; then
    log::info "Building the rewritten package for this system | flake='${flake}'"
    if ! out_path="$(build_package "${candidate}" "${flake}")"; then
      log::err "Build failed; nothing written | version='${version}'"
      exit 1
    fi
    bd_version="$("${out_path}/bin/bd" --version)"
    if [[ "${bd_version}" != *" ${version}"* ]]; then
      log::err "Built bd reports another version; nothing written | want='${version}' bd_version='${bd_version}' out_path='${out_path}'"
      exit 1
    fi
    log::info "Built | out_path='${out_path}' bd_version='${bd_version}'"
  fi

  if (( changed == 1 )); then
    write_mut "${file}" < "${candidate}"
  fi
  local skill_review
  skill_review="$(skills_to_review "${old_version}" "${version}")"

  report_dry_run "${SCRIPT_PATH}" "${args[@]}"
  local pair
  for pair in "${pairs[@]}"; do
    print -r -- "hash_${pair}"
  done
  cat <<EOF
old_version=${old_version}
version=${version}
file=${file}
changed=${changed}
out_path=${out_path}
bd_version=${bd_version}
skill_review=${skill_review}
dry_run=${DRY_RUN}
changes=${MUT_COUNT}
EOF
}

main "$@"
