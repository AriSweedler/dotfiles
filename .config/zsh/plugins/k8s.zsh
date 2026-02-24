eval "$(kubectl completion zsh)"

# brew install kubectx
alias kns="kubens"
alias kctx="kubectx"
alias k="kubectl"

function kwhoami() {
  local context
  context=$(kubectl config view --minify --output 'jsonpath={.current-context}')

  local namespace
  namespace=$(kubectl config view --minify --output 'jsonpath={.contexts[0].context.namespace}')
  : "${namespace:=default}"

  log::info "Inspected active context | context='${c_cyan}${context}${c_rst}' namespace='${c_cyan}${namespace}${c_rst}'"
  echo -n "kubectl --context '${context}' --namespace '${namespace}'" | pbcopy
  pbpaste
}
