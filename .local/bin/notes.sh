#!/bin/bash

############ The daykeeper file is a newline-separated list of dates ###########
TODAY="$(date '+%Y_%m_%d')"
BASE="$HOME/Desktop/notes"
DAYKEEPER_FILE="$BASE/.daykeeper"
pushd $BASE

function notes_past()
{
  echo "$BASE/$(cat .daykeeper | tail -$1 | head -1).md"
}
################################################################################

################### Add today to the DAYKEEPER_FILE if needed ##################
TODAYS_NOTES="$BASE/$TODAY.md"
MOST_RECENT_NOTES="$(notes_past 1)"

if test "$TODAYS_NOTES" != "$MOST_RECENT_NOTES"; then
  echo "$TODAY" >> "$DAYKEEPER_FILE"
fi

TODAYS_NOTES="$(notes_past 1)"
YESTERDAYS_NOTES="$(notes_past 2)"
################################################################################

############### Make sure we have today's notes in the git repo. ###############
############### Then open today & yesterday's notes ############################
touch "$TODAYS_NOTES"
git add "$TODAYS_NOTES"
vim "$TODAYS_NOTES" -c "vsp $YESTERDAYS_NOTES" -c "wincmd h"
