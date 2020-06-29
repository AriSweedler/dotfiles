#!/bin/bash

#Check to see if there's a file already
#If there isn't, make it and add a heading and start over
#If there is, add a timestamp

##################### Initialize variables and environment #####################
YEAR="$(date '+%Y')"
MONTH="$(date '+%b')"
DAY="$(date '+%d')"
TIME="$(date '+%R')"
BASE="/Users/ari/dev/journal"
TODAYS_NOTE="$BASE/$YEAR/$MONTH/$DAY.notes"
DAYKEEPER_FILE="$BASE/.daykeeper"
function notes_past()
{
  echo "$BASE/$(cat .daykeeper | tail -$1 | head -1).notes"
}

mkdir -p "$BASE/$YEAR/$MONTH"
pushd "$BASE/$YEAR"
################################################################################
########################## Create a new file if needed #########################
if test "$TODAYS_NOTE" != "$(notes_past 1)"; then
  # Today isn't the most recent entry in the daykeeper file! Commit the last
  # entry, and create this new one
  git add "$(notes_past 1)"
  git commit -m "Journal entry for $(notes_past 1)"
  echo "${YEAR}/${MONTH}/${DAY}" >> "$DAYKEEPER_FILE"

  # If the file for today doesn't already exist (only happens if it was manually
  # created) then create it and add it to git
  if test ! -e "$TODAYS_NOTE"; then
    printf "{{{ $MONTH $DAY, $YEAR\n}}}\n" > "$TODAYS_NOTE"
    git add "$TODAYS_NOTE"
    git add "$DAYKEEPER_FILE"
  fi
fi

################################################################################

#################### Open today's and yesterday's note file ####################
vim "$(notes_past 1)" -c "vsp $(notes_past 2)" -c "wincmd h" -c "normal gg"
