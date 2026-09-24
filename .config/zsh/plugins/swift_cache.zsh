# swift_cache.zsh — one cache tree for every Swift build in the dotfiles. A tool is compiled
# once per (source, toolchain) and every later call runs the cached binary; a toolchain
# upgrade invalidates everything at once. Callers use swift-run / swift-pkg / swift-cache
# (~/.config/bin) or these functions; none of them needs to know the layout below.
#
#   ${XDG_CACHE_HOME}/swift/
#   ├── CACHEDIR.TAG      backup tools skip the tree
#   ├── toolchain         "<stamp>\t<swiftc --version>": the version line, refreshed when the
#   │                     toolchain's swift-frontend changes (swiftc --version costs 0.6 s)
#   ├── module-cache/     swiftc -module-cache-path, shared by every compile
#   ├── bin/              single-file tools: <name>-<key> (key = sha256 of source + toolchain +
#   │                     flags, 12 hex), <name> -> current key, <name>.src = the source path
#   ├── pkg/<name>/       SwiftPM scratch path (replaces <package>/.build); .source, .toolchain
#   ├── swiftpm/          SwiftPM package and manifest cache (--cache-path)
#   └── derived/<name>/   xcodebuild DerivedData
#
# SWIFT_CACHE_SWIFTPM_DEFAULT=1 omits --cache-path so SwiftPM keeps its cache where Apple
# puts it (~/Library/Caches/org.swift.swiftpm); everything else is unchanged.

zmodload zsh/stat

(( ${+functions[log::info]} )) || source "${ZDOTDIR:-${HOME}/.config/zsh}/plugins/log.zsh"

typeset -g SWIFT_CACHE_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/swift"
typeset -ga SWIFT_CACHE_COMPILE_FLAGS=(-O)
typeset -gi SWIFT_CACHE_KEEP=3

# --- Tree ---

swift_cache::root() {
  if [[ ! -f "${SWIFT_CACHE_ROOT}/CACHEDIR.TAG" ]]; then
    mkdir -p "${SWIFT_CACHE_ROOT}"/{bin,pkg,swiftpm,module-cache,derived}
    print -r -- 'Signature: 8a477f597d28d172789f06886806bc55' > "${SWIFT_CACHE_ROOT}/CACHEDIR.TAG"
  fi
  print -r -- "${SWIFT_CACHE_ROOT}"
}

# The active toolchain's swift-frontend, whose mtime changes on every Xcode or CLT update.
swift_cache::_toolchain_stamp() {
  local dev frontend
  dev="$(xcode-select -p 2>/dev/null)" || dev=""
  for frontend in "${dev}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" "${dev}/usr/bin/swiftc"; do
    if [[ -n "${dev}" && -e "${frontend}" ]]; then
      print -r -- "${dev} $(zstat -F '%s' +mtime "${frontend:A}")"
      return 0
    fi
  done
  print -r -- "unknown"
}

swift_cache::toolchain() {
  local root stamp cached
  root="$(swift_cache::root)"
  stamp="$(swift_cache::_toolchain_stamp)"
  if [[ -r "${root}/toolchain" ]]; then
    cached="$(<"${root}/toolchain")"
    if [[ "${cached%%$'\t'*}" == "${stamp}" ]]; then
      print -r -- "${cached#*$'\t'}"
      return 0
    fi
  fi
  local version
  version="$(swiftc --version 2>/dev/null | head -1)" || { log::err "swiftc not found | fix='xcode-select --install'"; return 1; }
  print -r -- "${stamp}"$'\t'"${version}" > "${root}/toolchain"
  print -r -- "${version}"
}

# --- Single-file tools ---

swift_cache::_key() {
  local src="${1}" toolchain="${2}"
  { cat "${src}"; print -r -- "${toolchain}"; print -r -- "${SWIFT_CACHE_COMPILE_FLAGS[*]}"; } \
    | shasum -a 256 | cut -c1-12
}

# Print the binary for a single-file tool, compiling it first when no binary exists for the
# current source + toolchain. --force recompiles.
#   swift_cache::bin_for [--force] <file.swift>
swift_cache::bin_for() {
  local force=false
  [[ "${1:-}" == "--force" ]] && { force=true; shift; }
  local src="${1:?swift_cache::bin_for needs a .swift file}"
  [[ -r "${src}" ]] || { log::err "swift source not found | src='${src}'"; return 1; }
  src="${src:A}"
  local root toolchain key name bin
  root="$(swift_cache::root)"
  toolchain="$(swift_cache::toolchain)" || return 1
  key="$(swift_cache::_key "${src}" "${toolchain}")"
  name="${src:t:r}"
  bin="${root}/bin/${name}-${key}"
  if [[ "${force}" == false && -x "${bin}" ]]; then
    print -r -- "${bin}"
    return 0
  fi
  log::info "compiling swift tool | name='${name}' key='${key}' src='${src}'"
  local tmp="${bin}.tmp.$$"
  if ! swiftc "${SWIFT_CACHE_COMPILE_FLAGS[@]}" -module-cache-path "${root}/module-cache" -o "${tmp}" "${src}"; then
    rm -f "${tmp}"
    log::err "swift compile failed | src='${src}'"
    return 1
  fi
  mv -f "${tmp}" "${bin}"
  ln -sfn "${name}-${key}" "${root}/bin/${name}"
  print -r -- "${src}" > "${root}/bin/${name}.src"
  swift_cache::_trim_keys "${name}"
  print -r -- "${bin}"
}

# Keep the newest SWIFT_CACHE_KEEP binaries of a tool so a reverted source is a hit again.
swift_cache::_trim_keys() {
  setopt localoptions extendedglob
  local name="${1}" root
  root="$(swift_cache::root)"
  local -a keyed=( "${root}/bin/${name}"-[0-9a-f](#c12)(N.om) )
  (( ${#keyed} > SWIFT_CACHE_KEEP )) || return 0
  rm -f -- "${keyed[$(( SWIFT_CACHE_KEEP + 1 )),-1]}"
}

#   swift_cache::run [--force] <file.swift> [args...]
swift_cache::run() {
  local -a flags=()
  [[ "${1:-}" == "--force" ]] && { flags+=(--force); shift; }
  local src="${1:?swift_cache::run needs a .swift file}"; shift
  local bin
  bin="$(swift_cache::bin_for "${flags[@]}" "${src}")" || return 1
  "${bin}" "$@"
}

# --- SwiftPM packages ---

swift_cache::_pkg_name() { print -r -- "${${1:A}:t}"; }

# The release binary swift_cache::pkg_bin_for produces, without building anything.
#   swift_cache::pkg_binary <package-dir> [product]
swift_cache::pkg_binary() {
  local dir="${1:?package dir}" product="${2:-}"
  local name; name="$(swift_cache::_pkg_name "${dir}")"
  print -r -- "${SWIFT_CACHE_ROOT}/pkg/${name}/release/${product:-${name}}"
}

swift_cache::_pkg_stale() {
  local dir="${1}" bin="${2}" scratch="${3}" toolchain="${4}"
  [[ -x "${bin}" ]] || return 0
  [[ -r "${scratch}/.toolchain" && "$(<"${scratch}/.toolchain")" == "${toolchain}" ]] || return 0
  local f
  for f in "${dir}/Package.swift" "${dir}/Package.resolved"(N) "${dir}"/Sources/**/*(.N); do
    [[ "${f}" -nt "${bin}" ]] && return 0
  done
  return 1
}

swift_cache::_swiftpm_cache_flags() {
  [[ "${SWIFT_CACHE_SWIFTPM_DEFAULT:-0}" == "1" ]] && return 0
  print -r -- "--cache-path"
  print -r -- "${SWIFT_CACHE_ROOT}/swiftpm"
}

# Print a package's release binary, building it into the cache when it is missing, older
# than a source, or from another toolchain. --build always builds. SwiftPM's own up-to-date
# check costs seconds, so the staleness test here is what keeps a warm call fast.
#   swift_cache::pkg_bin_for [--build] [--product NAME] <package-dir>
swift_cache::pkg_bin_for() {
  local force=false product=""
  while (( $# > 1 )); do case "${1}" in
    --build)   force=true; shift ;;
    --product) product="${2:?--product needs a name}"; shift 2 ;;
    *) break ;;
  esac; done
  local dir="${1:?swift_cache::pkg_bin_for needs a package dir}"
  [[ -f "${dir}/Package.swift" ]] || { log::err "not a Swift package | dir='${dir}'"; return 1; }
  dir="${dir:A}"
  local root toolchain name scratch bin
  root="$(swift_cache::root)"
  toolchain="$(swift_cache::toolchain)" || return 1
  name="$(swift_cache::_pkg_name "${dir}")"
  scratch="${root}/pkg/${name}"
  bin="$(swift_cache::pkg_binary "${dir}" "${product}")"
  if [[ "${force}" == false ]] && ! swift_cache::_pkg_stale "${dir}" "${bin}" "${scratch}" "${toolchain}"; then
    print -r -- "${bin}"
    return 0
  fi
  local -a cache_flags=( "${(@f)$(swift_cache::_swiftpm_cache_flags)}" )
  cache_flags=( "${(@)cache_flags:#}" )
  log::info "swift build -c release | package='${name}' scratch='${scratch}' swiftpm_cache='${cache_flags[2]:-apple default}'"
  mkdir -p "${scratch}"
  if ! swift build -c release --package-path "${dir}" --scratch-path "${scratch}" "${cache_flags[@]}" >&2; then
    log::err "swift build failed | package='${name}'"
    return 1
  fi
  [[ -x "${bin}" ]] || { log::err "build produced no binary | expected='${bin}' hint='pass --product'"; return 1; }
  print -r -- "${toolchain}" > "${scratch}/.toolchain"
  print -r -- "${dir}" > "${scratch}/.source"
  print -r -- "${bin}"
}

#   swift_cache::pkg_run [--product NAME] <package-dir> [args...]
swift_cache::pkg_run() {
  local -a flags=()
  [[ "${1:-}" == "--product" ]] && { flags+=(--product "${2}"); shift 2; }
  local dir="${1:?swift_cache::pkg_run needs a package dir}"; shift
  local bin
  bin="$(swift_cache::pkg_bin_for "${flags[@]}" "${dir}")" || return 1
  "${bin}" "$@"
}

# --- xcodebuild ---

# A DerivedData directory for an xcodebuild-based installer, kept between runs so a rebuild
# is incremental. Pass it as -derivedDataPath.
#   swift_cache::derived_data_path <name>
swift_cache::derived_data_path() {
  local name="${1:?swift_cache::derived_data_path needs a name}" root
  root="$(swift_cache::root)"
  mkdir -p "${root}/derived/${name}"
  print -r -- "${root}/derived/${name}"
}

# --- Maintenance ---

swift_cache::_du() { du -sh "${1}" 2>/dev/null | cut -f1; }

swift_cache::status() {
  setopt localoptions extendedglob
  local root toolchain
  root="$(swift_cache::root)"
  toolchain="$(swift_cache::toolchain)" || return 1
  print -r -- "root       ${root}  ($(swift_cache::_du "${root}"))"
  print -r -- "toolchain  ${toolchain}"
  if [[ "${SWIFT_CACHE_SWIFTPM_DEFAULT:-0}" == "1" ]]; then
    print -r -- "swiftpm    apple default (SWIFT_CACHE_SWIFTPM_DEFAULT=1)"
  else
    print -r -- "swiftpm    ${root}/swiftpm ($(swift_cache::_du "${root}/swiftpm"))"
  fi
  print -r -- "modules    $(swift_cache::_du "${root}/module-cache")"
  print
  print -r -- "bin (single-file tools)"
  local link name src current key n
  for link in "${root}"/bin/*(N@); do
    name="${link:t}"
    current="$(readlink "${link}")"
    key="${current##*-}"
    src="$(<"${link}.src" 2>/dev/null)" || src="?"
    local -a keyed=( "${root}/bin/${name}"-[0-9a-f](#c12)(N.) )
    n=${#keyed}
    [[ -r "${src}" ]] || src="${src} (missing)"
    printf '  %-28s key=%s  keys=%d  %s  %s\n' "${name}" "${key}" "${n}" "$(swift_cache::_du "${link:A}")" "${src}"
  done
  print
  print -r -- "pkg (SwiftPM packages)"
  local scratch source bin
  for scratch in "${root}"/pkg/*(N/); do
    name="${scratch:t}"
    source="$(<"${scratch}/.source" 2>/dev/null)" || source="?"
    bin="${scratch}/release/${name}"
    local state="built"
    [[ -x "${bin}" ]] || state="no binary"
    [[ -r "${scratch}/.toolchain" && "$(<"${scratch}/.toolchain")" == "${toolchain}" ]] || state="${state}, stale toolchain"
    [[ -d "${source}" ]] || source="${source} (missing)"
    printf '  %-28s %-24s %s  %s\n' "${name}" "${state}" "$(swift_cache::_du "${scratch}")" "${source}"
  done
  print
  print -r -- "derived (xcodebuild)"
  local d
  for d in "${root}"/derived/*(N/); do
    printf '  %-28s %s\n' "${d:t}" "$(swift_cache::_du "${d}")"
  done
}

# Drop binaries no current symlink points at, and pkg/derived entries whose source is gone.
swift_cache::prune() {
  setopt localoptions extendedglob
  local root; root="$(swift_cache::root)"
  local f name link current
  for f in "${root}"/bin/*-[0-9a-f](#c12)(N.); do
    name="${${f:t}%-*}"
    link="${root}/bin/${name}"
    current="$(readlink "${link}" 2>/dev/null || true)"
    if [[ "${current}" != "${f:t}" ]]; then
      log::info "pruning stale binary | file='${f:t}'"
      rm -f -- "${f}"
    fi
  done
  local scratch source
  for scratch in "${root}"/pkg/*(N/); do
    source="$(<"${scratch}/.source" 2>/dev/null)" || source=""
    if [[ -z "${source}" || ! -d "${source}" ]]; then
      log::info "pruning package scratch whose source is gone | scratch='${scratch}' source='${source:-?}'"
      rm -rf -- "${scratch}"
    fi
  done
  log::info "swift cache pruned | root='${root}' size='$(swift_cache::_du "${root}")'"
}

# Rebuild one entry by name: a single-file tool (from its recorded source) or a package.
swift_cache::rebuild() {
  local name="${1:?swift_cache::rebuild needs a name}" root
  root="$(swift_cache::root)"
  if [[ -r "${root}/bin/${name}.src" ]]; then
    swift_cache::bin_for --force "$(<"${root}/bin/${name}.src")"
  elif [[ -r "${root}/pkg/${name}/.source" ]]; then
    swift_cache::pkg_bin_for --build "$(<"${root}/pkg/${name}/.source")"
  else
    log::err "nothing cached under that name | name='${name}' hint='swift-cache status'"
    return 1
  fi
}
