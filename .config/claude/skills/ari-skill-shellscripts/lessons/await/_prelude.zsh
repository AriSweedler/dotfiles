# Sourced by every lesson: the libraries and one helper. Not a lesson itself. The library is
# sourced here, before any lesson defines a function, so the await::_guard alias can expand.
set -uo pipefail
readonly SKILLS_DIR="${HOME}/.claude/skills"
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/await.zsh"
# Block until the person presses any key, read from the tty.
wait_key() { local k; read -k 1 -s k < /dev/tty; }
