function tennis() {
  # Bring me to the webpage necessary to reserve `Dolores Tennis Park Court
  # #3`. You can reserve this court 2 days in advance starting at 12 noon

  # Get the reservable date
  local mm dd dd2 yyyy
  mm=$(date +%m) || { echo "Unable to get month"; return 1; }
  dd=$(date +%d) || { echo "Unable to get day"; return 1; }
  yyyy=$(date +%Y) || { echo "Unable to get year"; return 1; }
  dd2=$(( dd + 2 ))
  local reservable_date="$mm/$dd2/$yyyy"

  # Construct the URL to look at the correct day
  court_url="https://www.spotery.com/spot/3681093"
  url="$court_url?psReservationDateStr=$reservable_date"
  open "$url"
}
