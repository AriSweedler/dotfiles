#!/bin/bash

############################# Initialize variables #############################
YEAR="$(date '+%Y')"
MONTH="$(date '+%b')"
DAY="$(date '+%d')"
BASE="$HOME/Desktop/notes_test"
TODAYS_NOTE="$BASE/$MONTH/$DAY.md"
DAYKEEPER_FILE="$BASE/.daykeeper"
function notes_past()
{
  echo "$BASE/$(cat .daykeeper | tail -$1 | head -1).md"
}
################################################################################
############################ Initialize environement ###########################
pushd $BASE
mkdir -p $MONTH
################################################################################
################### Add today to the DAYKEEPER_FILE if needed ##################
MOST_RECENT_NOTE="$(notes_past 1)"

if test "$TODAYS_NOTE" != "$MOST_RECENT_NOTE"; then
  echo "${MONTH}/${DAY}" >> "$DAYKEEPER_FILE"
fi

TODAYS_NOTE="$(notes_past 1)"
YESTERDAYS_NOTE="$(notes_past 2)"
################################################################################

############### Make sure we have today's notes in the git repo. ###############
############### Then open today & yesterday's notes ############################
if [ ! -e "$TODAYS_NOTE" ]; then
  echo "$MONTH $DAY, $YEAR" > "$TODAYS_NOTE"
  git add "$TODAYS_NOTE"
fi
vim "$TODAYS_NOTE" -c "vsp $YESTERDAYS_NOTE" -c "wincmd h"
