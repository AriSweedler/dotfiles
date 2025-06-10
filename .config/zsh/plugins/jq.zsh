function jq::flatten() {
  prog="$(cat << EOF
import json
import sys

def flatten(obj, path=""):
    def format_key(k):
        if isinstance(k, int):
            return f"[{k}]"
        elif k.isidentifier():
            return f".{k}"
        else:
            return f'["{k}"]'

    if isinstance(obj, dict):
        for k, v in obj.items():
            key = format_key(k)
            new_path = f"{path}{key}" if path else (k if k.isidentifier() else f'["{k}"]')
            yield from flatten(v, new_path)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            new_path = f"{path}[{i}]"
            yield from flatten(v, new_path)
    else:
        yield path, obj

def main():
    if sys.stdin.isatty():
        print("No JSON input provided. Pipe JSON to stdin.", file=sys.stderr)
        sys.exit(1)

    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)

    for key, value in flatten(data):
        print(f"{key}: {value}")

if __name__ == "__main__":
    main()
EOF
)"
  python3 -c "${prog}"
}

function jq::fzf() {
  # Get stdin
  local input
  if [ -t 0 ]; then
    log::warn "No stdin given - exiting"
    return 1
  else
    input="$(cat -)"
  fi

  # Get user selection from fzf
  local selection
  if ! selection="$(echo "${input}" | jq::flatten | fzf)"; then
    log::warn "Nothing selected - exiting"
    return 1
  fi

  # Give the output
  local key=".${selection%%:*}"
  echo "${input}" | run_cmd jq "${key}"

  # And put the new command on the user's path
  if ! cmd=( $(fc -ln | grep "${funcstack[1]}" | tail -1) ); then
    log::err "Failed to find the most recent '${funcstack[1]}' command"
    return
  fi
  echo -n "${cmd[@]}" | sed "s|${funcstack[1]}|jq '"${key}"'|" | pbcopy
  log::info "Put doctored command on clipboard | pbpaste='${c_cyan}$(pbpaste)${c_rst}'"
}
