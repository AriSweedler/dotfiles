#!/bin/bash

#Check to see if there's a file already
#If there isn't, make it and add a heading and start over
#If there is, add a timestamp

##################### Initialize variables and environment #####################
YEAR="$(date '+%Y')"
MONTH="$(date '+%b')"
DAY="$(date '+%d')"
TIME="$(date '+%R')"
BASE="$HOME/Desktop/notes"
TODAYS_NOTE="$BASE/$YEAR/$MONTH/$DAY.notes"
DAYKEEPER_FILE="$BASE/.daykeeper"
DAILY_TASKS="$BASE/etc/vitamins.notes"
function notes_past()
{
  echo "$BASE/$(cat $DAYKEEPER_FILE | tail -$1 | head -1).notes"
}

mkdir -p "$BASE/$YEAR/$MONTH"
pushd "$BASE"
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
    # Prepopulate the new notes file
    printf "{{{ $MONTH $DAY, $YEAR\n" > "$TODAYS_NOTE"
    cat "$DAILY_TASKS" >> "$TODAYS_NOTE"
    printf "}}}\n" >> "$TODAYS_NOTE"

    # And add it to git
    git add "$TODAYS_NOTE"
    git add "$DAYKEEPER_FILE"
  fi
fi

################################################################################

#################### Open today's and yesterday's note file ####################
vim "$(notes_past 1)" -c "vsp $(notes_past 2)" -c "wincmd h" -c "normal gg"
git add "$TODAYS_NOTE"
