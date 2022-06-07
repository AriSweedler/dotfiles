export ILLSYS="illumio-system"

# Shortcuts for kubectl
alias k="kubectl"
alias kk="kubectl -n kube-system"
alias ki='kubectl -n "$ILLSYS"'

# Init the convergence nginx deployment
function init_convergence_deployment() {
  # TODO find and apply the yml file I use for the integration test
  echo "Not implemented yet"
}

# Easily scale the convergence nginx deployment for containers
function scale_replicas() {
  # Note: The nginx deployment can be initialized with
  # kubectl apply -f https://k8s.io/examples/controllers/nginx-deployment.yaml

  if [ -n "$1" ]; then
    # Do the work
    kubectl --namespace convergence scale deployments/nginx-deployment-convergence --replicas="$1"

    # Log it
    xd --logs-write "scaled replicas to $1"
  else
    echo "No \$1 given. Simply displaying deployments"
  fi

  # Confirm it went through
  kubectl get deployments
  echo ""
}

# Macro to make data collection easier
function scale_data() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "You need to give two arguments. Scale from & Scale to."
  fi
  scale_replicas "$1"
  read _ || :
  xd --logs-clear
  scale_replicas "$2"
  read _ || :
  xd --logs-nexus
}

