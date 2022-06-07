# cd to source directory
function cso() {
  double_cd "$HOME/Desktop/source/hawkeye" "$1"
}

# cd to my devenv (groot)
function cde() {
  double_cd "$HOME/devenv/groot" "$1"
}

# cd to my devenv
function cdee() {
  double_cd "$HOME/devenv" "$1"
}

# cd to my nexus folder
function cdn() {
  double_cd "$HOME/Desktop/nexus" "$1"
}

# cd to my vagrant machine
function cv() {
  double_cd "$HOME/workspace/hawkeye-tools/output" "$1"
}

# cd to my jiras folder
function cjira() {
  local -r jira_dir="$HOME/Documents/OneDrive - Illumio/jiras"

  if [ -z "$1" ]; then
    double_cd "$jira_dir"
    return
  fi

  if echo "$1" | grep -q 'EYE-\d\d\d\d\d'; then
    local -r eye_dir="$jira_dir/$1"
    ensure_dir_created "$eye_dir"
  fi

  double_cd "$jira_dir" "$1"
}

# cd to Ultron
function cult() {
  double_cd "$HOME/workspace/ultron" "$1"
}

# cd to playground
function cplay() {
  double_cd "$HOME/workspace/playground" "$1"
}
