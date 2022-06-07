#!/bin/bash -exu

function iks::kubectl-new-key() {
  # Download IT's key so we can log into the 994522649553 machine
  b-echo "Getting new key from IT"
  local -r awk_config_bucket="https://s3-us-west-2.amazonaws.com/devops-shared-bucket/ecr/config"
  curl --fail "$awk_config_bucket" > ~/.aws/config
}

function ibmcloud-login() {
  # Make sure you've already authenticated Okta SSO in your browser
  ibmcloud login --sso -a cloud.ibm.com -r us-south -g "Illumio Engineering"
}

function iks::kubectl-aws-login() {
  local -r registry="$1"
  local -r key="$2"

  b-echo "Logging into AWS docker registry $registry to get a token"
  echo "Using a containerized script to do this. Logging in will give us an access token."
  local -r login="$(echo "$key" | docker login --username AWS --password-stdin "$registry" 2>&1)"
  if ! echo "$login" | grep "Login Succeeded"; then
    b-echo "Login failed vvv"
    echo "$login"
    b-echo "Login failed ^^^"
    return 1
  fi

}

function iks::kubectl-aws-key-to-token() {
  local -r docker_config="$HOME/.docker/config.json"
  local -r region="us-west-2"
  local -r registry="994522649553.dkr.ecr.$region.amazonaws.com"

  b-echo "Getting a key from logging into AWS as an Illumio employee"
  local -r key="$(docker run -it -v ~/.aws:/root/.aws -v $(pwd):/aws amazon/aws-cli ecr get-login-password --region "$region")"
  printf "40 chars of the key: '%s'\n" "$(echo "$key" | cut -c 1-40)"

  b-echo "logging in to get token in cleartext"
  iks::kubectl-aws-login "$registry" "$key"
  if grep 'credsStore' "$docker_config"; then
    echo "Trying to re-write 'auths' key, but without credStrore"
    local -r json="$(jq '{auths: .auths}' < "$docker_config")"
    echo "$json" > "$docker_config"
    iks::kubectl-aws-login "$registry" "$key"
  fi

  b-echo "Reading the token"
  local -r token="$(jq ".auths | .[\"$registry\"] | .auth" < "$docker_config")"
  if [ "$token" = "null" ]; then
    b-echo "Docker config vvv (getting token failed)"
    cat "$docker_config"
    b-echo "Docker config ^^^ (getting token failed)"
    echo "Make sure the 'auth' token is in clear text. Might need to remove the 'credsStore' key and re-log to accomplish this. Or something else"
    return 1
  fi
  printf "40 chars of the token: '%s'\n" "$(echo "$token" | tr -d '"' | cut -c 1-40)"
}

function iks::kubectl-token-to-k8s-secret() {
  # Use the access token to create a k8s secret. Put the secret into k8s so the cluster can use it to pull images
  b-echo "Updating k8s secret"
  kubectl delete secrets -n illumio-system illumio-dev-ecr
  kubectl create secret generic illumio-dev-ecr -n illumio-system --from-file=.dockerconfigjson="$HOME/.docker/config.json" --type=kubernetes.io/dockerconfigjson
}

function iks::kubectl-set-ibmcloud-config() {
  # Update the auth in the k8s config file.
  # Update the 'context's auth.
  b-echo "Setting k8s context to be my IKS cluster"
  ibmcloud ks cluster config --cluster c0dfodid0rvaoctejv00
}

function iks::kubectl-cleanup() {
  b-echo "Removing cleartext credentials"
  rm "$HOME/.docker/config.json"
  echo "Done"
}

function _run-fxn() {
  if [ -n "$failed" ]; then return 1; fi
  if ! "$@"; then
    echo "FAILED: '$*'"
    failed=true
    return 1
  fi
}

# Update the kubectl secret, point kubectl to IKS
function iks-kubectl-refresh() {
  unset failed
  [ "$1" = "login" ] && ibmcloud-login
  _run-fxn iks::kubectl-new-key
  _run-fxn iks::kubectl-aws-key-to-token
  _run-fxn iks::kubectl-set-ibmcloud-config
  _run-fxn iks::kubectl-token-to-k8s-secret
  _run-fxn iks::kubectl-cleanup

  b-echo "Checking to see that this worked:"
  _run-fxn kubectl get pods -A | grep ven
}

