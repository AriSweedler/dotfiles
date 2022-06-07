function hawk::branch_to_version() {
  local -r branch="${1:?}"
  if ! git rev-parse "$branch" &>/dev/null; then
    echo "ERROR:: Could not find ref '$branch'"
    return 1
  fi
  git show "$branch":CMakeLists.txt | awk '/project.*VERSION/ {print $5}'
}

# Produce a CSV for all versions
function hawk::all_versions() {
  printf "%s,%s\n" "branch" "version"
  for branch in $(git branch --remote | awk '{print $1}' | grep 'trains\|dev'); do
    version="$(hawk::branch_to_version "$branch" 2>/dev/null)"
    [ -z "$version" ] && continue
    printf "%s,%s\n" "$branch" "$version"
  done
}
