# Tests for swift_cache.zsh: the cache key, the trim and the prune, which decide what is rebuilt and
# what is deleted. swiftc, swift and xcode-select are stubs on PATH, so nothing compiles and the run
# takes a second; the cache root is a temp dir.
# Only runs when OTTO_TEST__ZSH_PLUGINS_SWIFT_CACHE=true
[[ "$OTTO_TEST__ZSH_PLUGINS_SWIFT_CACHE" == "true" ]] || return 0

local _pass=0 _fail=0
local _plugins="${${(%):-%x}:A:h}"
source "${_plugins}/log.zsh"
local _dir; _dir="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/swift-cache-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "${_dir}"' EXIT

function _t() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then log::info "PASS: ${name}"; ((_pass++))
  else log::err "FAIL: ${name}"; print -u2 "  expected: ${expected}"; print -u2 "  actual:   ${actual}"; ((_fail++)); fi
}

# The stubs. swiftc --version prints ${_dir}/version; a compile writes an executable that prints the
# source's first line, unless the source says FAIL, and logs one line per compile. swift build writes
# release/<name> under the scratch path and logs. xcode-select points at a fake developer dir whose
# swiftc mtime is the toolchain stamp.
mkdir -p "${_dir}/stubs" "${_dir}/dev/usr/bin" "${_dir}/src"
print -r -- "Swift version 6.0" > "${_dir}/version"
: > "${_dir}/dev/usr/bin/swiftc"
cat > "${_dir}/stubs/swiftc" <<EOF
#!/bin/sh
if [ "\$1" = --version ]; then echo called >> "${_dir}/version.log"; cat "${_dir}/version"; exit 0; fi
out=""; src=""
while [ \$# -gt 0 ]; do case "\$1" in -o) out="\$2"; shift 2 ;; -module-cache-path) shift 2 ;; -*) shift ;; *) src="\$1"; shift ;; esac; done
echo "\${src}" >> "${_dir}/compile.log"
grep -q FAIL "\${src}" && { echo "error: boom" >&2; exit 1; }
printf '#!/bin/sh\necho "%s" "\$@"\n' "\$(head -n 1 "\${src}")" > "\${out}"; chmod +x "\${out}"
EOF
cat > "${_dir}/stubs/swift" <<EOF
#!/bin/sh
scratch=""; pkg=""
while [ \$# -gt 0 ]; do case "\$1" in --scratch-path) scratch="\$2"; shift 2 ;; --package-path) pkg="\$2"; shift 2 ;; *) shift ;; esac; done
echo "\${pkg}" >> "${_dir}/build.log"
mkdir -p "\${scratch}/release"; name="\$(basename "\${pkg}")"
printf '#!/bin/sh\necho pkg-%s\n' "\${name}" > "\${scratch}/release/\${name}"; chmod +x "\${scratch}/release/\${name}"
EOF
printf '#!/bin/sh\necho %s\n' "${_dir}/dev" > "${_dir}/stubs/xcode-select"
chmod +x "${_dir}/stubs"/*
path=("${_dir}/stubs" "${path[@]}")
export XDG_CACHE_HOME="${_dir}/cache"
source "${_plugins}/swift_cache.zsh"
local R="${XDG_CACHE_HOME}/swift"
_compiles() { [[ -f "${_dir}/compile.log" ]] && wc -l < "${_dir}/compile.log" | tr -d ' ' || print 0; }
_keyed() { setopt localoptions extendedglob; local -a k=( "${R}/bin/${1}"-[0-9a-f](#c12)(N.) ); print -r -- ${#k}; }

# ── the tree ──
_t "root: the tree is made with a CACHEDIR.TAG" "${R}" "$(swift_cache::root)"
_t "root: backup tools skip it" "Signature: 8a477f597d28d172789f06886806bc55" "$(<"${R}/CACHEDIR.TAG")"

# ── single-file tools: compile once, hit after ──
print -r -- "one" > "${_dir}/src/hello.swift"
_t "bin_for: the first call compiles and runs" "one a b" "$(swift_cache::run "${_dir}/src/hello.swift" a b 2>/dev/null)"
_t "bin_for: one compile" "1" "$(_compiles)"
_t "bin_for: the second call is a hit" "one" "$(swift_cache::run "${_dir}/src/hello.swift" 2>/dev/null)"
_t "bin_for: still one compile" "1" "$(_compiles)"
_t "toolchain: swiftc --version ran once, then the stamp cached it" "1" "$(wc -l < "${_dir}/version.log" | tr -d ' ')"
local first_key; first_key="$(readlink "${R}/bin/hello")"
_t "bin_for: the current link and the recorded source" "${_dir}/src/hello.swift" "$(<"${R}/bin/hello.src")"

# ── a changed source is a new key; a revert is a hit on the old one ──
print -r -- "two" > "${_dir}/src/hello.swift"
_t "edit: the new source runs" "two" "$(swift_cache::run "${_dir}/src/hello.swift" 2>/dev/null)"
_t "edit: it compiled" "2" "$(_compiles)"
_t "edit: two keyed binaries kept" "2" "$(_keyed hello)"
print -r -- "one" > "${_dir}/src/hello.swift"
_t "revert: the old binary runs" "one" "$(swift_cache::run "${_dir}/src/hello.swift" 2>/dev/null)"
_t "revert: no compile" "2" "$(_compiles)"
_t "revert: the current link points back at it" "${first_key}" "$(readlink "${R}/bin/hello")"

# ── a toolchain upgrade invalidates every key ──
print -r -- "Swift version 6.1" > "${_dir}/version"
touch -t 203001010000 "${_dir}/dev/usr/bin/swiftc"
_t "toolchain: a new frontend mtime re-reads the version" "Swift version 6.1" "$(swift_cache::toolchain)"
swift_cache::run "${_dir}/src/hello.swift" >/dev/null 2>&1
_t "toolchain: the same source compiles again under it" "3" "$(_compiles)"

# ── --force, the trim, a failed compile ──
swift_cache::bin_for --force "${_dir}/src/hello.swift" >/dev/null 2>&1
_t "--force: compiles on a hit" "4" "$(_compiles)"
local v
for v in three four five; do print -r -- "${v}" > "${_dir}/src/hello.swift"; swift_cache::run "${_dir}/src/hello.swift" >/dev/null 2>&1; done
_t "trim: only the newest SWIFT_CACHE_KEEP binaries stay" "${SWIFT_CACHE_KEEP}" "$(_keyed hello)"
_t "trim: the current one is among them" "yes" "$([[ -x "${R}/bin/$(readlink "${R}/bin/hello")" ]] && print yes || print no)"
local before_link; before_link="$(readlink "${R}/bin/hello")"
print -r -- "FAIL" > "${_dir}/src/hello.swift"
swift_cache::bin_for "${_dir}/src/hello.swift" >/dev/null 2>&1; local rc=$?
_t "compile failure: exit 1" "1" "${rc}"
_t "compile failure: the current link is unchanged" "${before_link}" "$(readlink "${R}/bin/hello")"
_t "compile failure: no temp binary left" "0" "$(print -l "${R}"/bin/*.tmp.*(N) | grep -c . )"
swift_cache::bin_for "${_dir}/src/missing.swift" >/dev/null 2>&1; rc=$?
_t "a missing source: exit 1" "1" "${rc}"

# ── prune ──
print -r -- "x" > "${R}/bin/hello-aaaaaaaaaaaa"; chmod +x "${R}/bin/hello-aaaaaaaaaaaa"
swift_cache::prune >/dev/null 2>&1
_t "prune: every binary the current link does not name is gone" "1" "$(_keyed hello)"
_t "prune: the current binary stays" "yes" "$([[ -x "${R}/bin/hello" ]] && print yes || print no)"

# ── packages ──
mkdir -p "${_dir}/pkgs/tool/Sources/tool"
print -r -- "// swift-tools-version:5.9" > "${_dir}/pkgs/tool/Package.swift"
print -r -- "print(1)" > "${_dir}/pkgs/tool/Sources/tool/main.swift"
touch -t 202601010000 "${_dir}/pkgs/tool/Package.swift" "${_dir}/pkgs/tool/Sources/tool/main.swift"
_builds() { [[ -f "${_dir}/build.log" ]] && wc -l < "${_dir}/build.log" | tr -d ' ' || print 0; }
_t "pkg: the first call builds and runs" "pkg-tool" "$(swift_cache::pkg_run "${_dir}/pkgs/tool" 2>/dev/null)"
_t "pkg: one build, into the cache" "1:${R}/pkg/tool/release/tool" "$(_builds):$(swift_cache::pkg_binary "${_dir}/pkgs/tool")"
swift_cache::pkg_run "${_dir}/pkgs/tool" >/dev/null 2>&1
_t "pkg: a warm call skips SwiftPM" "1" "$(_builds)"
touch "${_dir}/pkgs/tool/Sources/tool/main.swift"
swift_cache::pkg_run "${_dir}/pkgs/tool" >/dev/null 2>&1
_t "pkg: a source newer than the binary rebuilds" "2" "$(_builds)"
print -r -- "Swift version 6.2" > "${_dir}/version"; touch -t 203101010000 "${_dir}/dev/usr/bin/swiftc"
swift_cache::pkg_run "${_dir}/pkgs/tool" >/dev/null 2>&1
_t "pkg: another toolchain rebuilds" "3" "$(_builds)"
swift_cache::pkg_bin_for --product nope "${_dir}/pkgs/tool" >/dev/null 2>&1; rc=$?
_t "pkg: a product the build did not make is exit 1" "1" "${rc}"
swift_cache::pkg_bin_for "${_dir}/src" >/dev/null 2>&1; rc=$?
_t "pkg: a directory with no Package.swift is exit 1" "1" "${rc}"

mkdir -p "${_dir}/pkgs/gone/Sources"; print -r -- "//" > "${_dir}/pkgs/gone/Package.swift"
swift_cache::pkg_bin_for "${_dir}/pkgs/gone" >/dev/null 2>&1; rm -rf "${_dir}/pkgs/gone"
swift_cache::prune >/dev/null 2>&1
_t "prune: a package whose source is gone is dropped" "no" "$([[ -d "${R}/pkg/gone" ]] && print yes || print no)"
_t "prune: a package whose source is there stays" "yes" "$([[ -x "${R}/pkg/tool/release/tool" ]] && print yes || print no)"

# ── rebuild ──
local nb; nb="$(_builds)"
swift_cache::rebuild tool >/dev/null 2>&1
_t "rebuild: a package by name builds again" "$(( nb + 1 ))" "$(_builds)"
swift_cache::rebuild nothing-here >/dev/null 2>&1; rc=$?
_t "rebuild: an unknown name is exit 1" "1" "${rc}"

if (( _fail )); then log::err "swift_cache: ${_pass} passed, ${_fail} failed"; return 1; fi
log::info "swift_cache: all ${_pass} passed"
