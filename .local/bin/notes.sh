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
TODAYS_NOTE="$BASE/$MONTH/$DAY.md"
DAYKEEPER_FILE="$BASE/.daykeeper"
function notes_past()
{
  echo "$BASE/$(cat .daykeeper | tail -$1 | head -1).md"
}

pushd $BASE
mkdir -p $MONTH
################################################################################
########################## Create a new file if needed #########################
MOST_RECENT_NOTE="$(notes_past 1)"
if test "$TODAYS_NOTE" != "$MOST_RECENT_NOTE"; then
  # Add today to the daykeeper file
  echo "${MONTH}/${DAY}" >> "$DAYKEEPER_FILE"

  # Create the file, add the 'date' heading, add the file to git
  if test ! -e "$TODAYS_NOTE"; then
    echo "# $MONTH $DAY, $YEAR" > "$TODAYS_NOTE"
    git add "$TODAYS_NOTE"
  fi
fi

TODAYS_NOTE="$(notes_past 1)"
YESTERDAYS_NOTE="$(notes_past 2)"
################################################################################

############### Make sure we have today's notes in the git repo. ###############
############### Then open today & yesterday's notes ############################
echo "## $TIME" >> "$TODAYS_NOTE"
vim "$TODAYS_NOTE" -c "vsp $YESTERDAYS_NOTE" -c "wincmd h" -c "normal Go"
