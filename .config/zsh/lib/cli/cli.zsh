# zsh/lib/cli/cli.zsh — the cli library: a program's command line declared once, and from that
# declaration its help, its flag parser, a linter and a compiled zsh completion. Any zsh program
# may use it: dotfiles does (lib/cli.zsh there), and so can a script of either tier.
#
#   CLI_PROG=myprog                      the program's name, as typed (required)
#   CLI_COMPLETION_FILE=…/_myprog        where `completion write` keeps the compiled function
#   source "${HOME}/.config/zsh/lib/cli/cli.zsh"
#
# Then declare (verb.zsh: verb::define, verb::usage, verb::flag, verb::arg, …; kind.zsh:
# kind::define), parse with verb::parse VERB "$@", print help with verb::help VERB, lint with
# spec::lint, and compile with completion::emit (emit.zsh, sourced by cli::load_emit when the
# program compiles, so startup does not pay for it).
#
# verb::parse reports a usage error through usage_error MESSAGE; a program that defines its own
# keeps it, else the one below prints the message and exits 64. Colours come from c_grey, c_rst
# and c_bold, which the logging library sets.

typeset -g CLI_LIB="${${(%):-%x}:A:h}"
: "${CLI_PROG:?set CLI_PROG, the program name, before sourcing cli.zsh}"
source "${CLI_LIB}/verb.zsh"
source "${CLI_LIB}/kind.zsh"
source "${CLI_LIB}/spec.zsh"

# cli::load_emit: define completion::emit, the compiler's back end.
cli::load_emit() { (( ${+functions[completion::emit]} )) || source "${CLI_LIB}/emit.zsh"; }

if (( ! ${+functions[usage_error]} )); then
  usage_error() {
    print -u2 -r -- "[ERROR] ${CLI_PROG}: ${1}"
    exit 64
  }
fi
