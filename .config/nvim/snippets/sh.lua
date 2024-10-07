print("[ARI] Loading shell snippets (ari.snippets)")

-- Add snippets for shell scripting
return {
	-- First snippet: argparse
	s(
		"argparse",
		fmt([[
local {} my_flag
while (( $# > 0 )); do
  case "$1" in
    --key) {}="${{2:?}}"; shift 2 ;;
    --flag) my_flag=true; shift ;;
    *) echo "Unknown arg | func='${{BASH_SOURCE[0]}}' arg='$1'"; exit 1 ;;
  esac
done
]],
			{ i(1), i(2) } -- Use i(1) for the first placeholder and i(2) for the second
		)
	),

	-- Second snippet: logsuite
	s(
		"logsuite",
		t(
			[[
## The classic log suite
c_red='\e[31m'; c_green='\e[32m'; c_rst='\e[0m'
log::ts() { date "+%Y-%m-%dT%T.%N"; }
log::err() { echo -e "${c_red}$(log::ts) ERROR::${c_rst}" "$@" >&2; }
log::info() { echo -e "${c_green}$(log::ts) INFO::${c_rst}" "$@" >&2; }
run_cmd() { log::info "$@"; "$@" && return; rc=$?; log::err "cmd '$*' failed: $rc"; return $rc; }
]]
		)
	),
}
