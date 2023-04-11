function eye() {
  local -r ticket="${1:?}"

  # Only take the number
  local -r num="$(grep -o "\d\+" <<< "$ticket")"

  # Open the jira ticket
  open "https://jira.illum.io/browse/EYE-$num"
}

function jira::open_eye() {
  local current_branch
  if current_branch="$(git branch --show-current)"; then
    eye "$current_branch"
  fi
}

function jira::sr::extract() {
  local -r d_dir="${1:?}"
  if [ ! -d "$d_dir" ]; then
    echo "No './$d_dir' dir to get sr from"
    return 1
  fi

  local -r sr_dir="${2:?}"
  mkdir -p "$sr_dir" || return 1
  find "$d_dir" -name "*.tgz" -exec tar xzf {} -C "$sr_dir" \;
  find "$d_dir" -name "*.zip" -exec unzip {} -d "$sr_dir"  \;
  b_echo
  printf "Done!\n\n"
  ls *
}

function artifacts::sr() {
  scoop_downloads
  jira::sr::extract "downloads" "sr"
}

