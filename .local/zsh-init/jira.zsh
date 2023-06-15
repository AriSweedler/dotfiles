function eye() {
  local -r ticket="${1:?}"

  # Only take the number
  local -r num="$(grep -o "\d\+" <<< "$ticket")"

  # Open the jira ticket
  open "https://jira.illum.io/browse/EYE-$num"
}
