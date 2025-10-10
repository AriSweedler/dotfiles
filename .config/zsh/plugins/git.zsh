save_file_from_commit() {
  local file="${1:?path/to/file required}"
  local ref="${2:?refspec (SHA/branch/tag) required}"

  # Resolve the refspec to a commit SHA for the filename suffix.
  local commit_sha
  if ! commit_sha=$(git rev-parse --verify -q "${ref}^{commit}"); then
    log::err "Invalid refspec | ref='${ref}'"
    return 1
  fi

  # 7-char, underscore-padded short SHA
  local short_sha="${commit_sha:0:7}"
  local padded_sha
  padded_sha=$(printf "%-7s" "$short_sha" | tr ' ' '_')

  # Derive output filename
  local out="${file}.sha-${padded_sha}"

  # Ensure the blob exists at that refspec
  if ! git cat-file -e "${ref}:${file}" 2>/dev/null; then
    log::err "File not found at ref | file='${file}' ref='${ref}'"
    return 1
  fi

  # Extract file from the given refspec
  if ! git show "${ref}:${file}" > "$out"; then
    log::err "Failed to read file from ref | file='${file}' ref='${ref}'"
    return 1
  fi

  log::info "Wrote file from ref to out | file='${file}' ref='${ref}' sha='${commit_sha}' out='${out}'"
}
