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
daily_tasks="$base/etc/tasks/daily.notes"
weekly_tasks="$base/etc/tasks/$(date +%A | tr 'A-Z' 'a-z').notes"

pushd "$base"

function notes_past()
{
  echo "$base/$(cat $daykeeper_file | tail -$1 | head -1).notes"
}
function initialize()
{
  git init
  git commit --allow-empty -m 'first commit'
  touch "$daykeeper_file"
}

mkdir -p "$base/$year/$month"
if ! ls "$base/$year/$month"; then echo "something is wrong"; exit 1; fi
if [ ! -f "$daykeeper_file" ]; then initialize; fi

# TODO standardize IF statements in here
################################################################################
########################## Create a new file if needed #########################
if test "$todays_note" != "$(notes_past 1)"; then
  # Today isn't the most recent entry in the daykeeper file! Commit the last
  # entry, and create this new one
  test -f "$(notes_past 1)" && git add "$(notes_past 1)"
  git commit -m "Journal entry for $(notes_past 1)"
  echo "${year}/${month}/${day}" >> "$daykeeper_file"

  # link to A, and name that file B
  today_symlink="$base/today.notes"
  ln -f -s "$todays_note" "$today_symlink"

  # If the file for today doesn't already exist (only happens if it was manually
  # created) then create it and add it to git
  if test ! -e "$todays_note"; then
    # Prepopulate the new notes file
    printf "{{{ $month $day, $year\n" > "$todays_note"
    test -f "$daily_tasks" && cat "$daily_tasks" >> "$todays_note"
    test -f "$weekly_tasks" && cat "$weekly_tasks" >> "$todays_note"
    printf "}}}\n" >> "$todays_note"

    # And add it to git
    git add "$todays_note"
    git add "$daykeeper_file"
  fi
fi

################################################################################

################################## Open files ##################################
files_to_open=""
for i in {1..5}; do
  files_to_open="$files_to_open $(notes_past "$i")"
done
# Open a week of notes in buffers.
# Use the `Notes` command to get that nice view split
vim $files_to_open -c"Notes"
git add "$todays_note"
