eval "$(kubectl completion zsh)"

# brew install kubectx
alias kns="kubens"
alias kctx="kubectx"
alias kx="kubectx"
alias k="kubectl"

function kxx() {
  # get current context and namespace
  local ctx ns
  ctx="$(kubectl config current-context)"
  ns="$(kubectl config view --minify --output 'jsonpath={..namespace}')"

  # if namespace is empty, default to 'default'
  if [[ -z "$ns" ]]; then
    ns="default"
  fi

  echo -n "kubectl --context $ctx --namespace $ns" | tee >(cat) | pbcopy
  echo
}
