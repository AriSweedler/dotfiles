#!/bin/bash

#Check to see if there's a file already
#If there isn't, make it and add a heading and start over
#If there is, add a timestamp

##################### Initialize variables and environment #####################
year="$(date '+%Y')"
month="$(date '+%b')"
day="$(date '+%d')"
time="$(date '+%R')"
base="$HOME/Desktop/notes"
todays_note="$base/$year/$month/$day.notes"
daykeeper_file="$base/.daykeeper"
daily_tasks="$base/etc/vitamins.notes"
function notes_past()
{
  echo "$base/$(cat $daykeeper_file | tail -$1 | head -1).notes"
}

mkdir -p "$base/$year/$month"
if ! ls "$base/$year/$month"; then
  echo "something is wrong"
  exit 1
fi
pushd "$base"
################################################################################
########################## Create a new file if needed #########################
if test "$todays_note" != "$(notes_past 1)"; then
  # Today isn't the most recent entry in the daykeeper file! Commit the last
  # entry, and create this new one
  git add "$(notes_past 1)"
  git commit -m "Journal entry for $(notes_past 1)"
  echo "${year}/${month}/${day}" >> "$daykeeper_file"

  # link to A, and name that file B
  today_symlink="$base/today.notes"
  rm "$today_symlink"
  ln -s "$todays_note" "$today_symlink"

  # If the file for today doesn't already exist (only happens if it was manually
  # created) then create it and add it to git
  if test ! -e "$todays_note"; then
    # Prepopulate the new notes file
    printf "{{{ $month $day, $year\n" > "$todays_note"
    cat "$daily_tasks" >> "$todays_note"
    printf "}}}\n" >> "$todays_note"

    # And add it to git
    git add "$todays_note"
    git add "$daykeeper_file"
  fi
fi

################################################################################

#################### Open today's and yesterday's note file ####################
vim "$(notes_past 1)" -c "vsp $(notes_past 2)" -c "wincmd h" -c "normal gg"
git add "$todays_note"
