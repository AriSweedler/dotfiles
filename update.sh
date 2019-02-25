#!/usr/bin/env bash

# Place the most up-to-date version of a dotfile into this repo. Make a backup
# if needed.
REPO="$HOME/dotfiles"

############################### backup function ################################
function backup() {
  ORIGINAL="$1"
  NEW="$2"
  if [ ! -f $ORIGINAL ]; then
    echo "  file $ORIGINAL cannot be backed up because it doesn't exist"
    return 1
  fi
  TIME=$(date +"%Y%m%d%H%M%S")
  FILE=$(basename ${ORIGINAL})
  BACKUP="/tmp/${TIME}-${FILE}"
  diff $ORIGINAL $NEW > $BACKUP
  echo "  machine's $FILE is outta date. Making a backup at $BACKUP"
}

######## if we don't have the repo, then there's no point in continuing ########
if [ ! -d "$REPO/.git" ]; then
  echo "No repo found. Please git clone git@github.com:AriSweedler/dotfiles.git"
  exit 1
fi


############################### Begin script body ##############################
cd $REPO
printf "pulling latest version of the repo... "
git pull

####### for every dotfile in the repo (including stuff like '.vim/file') #######
printf "Updating each dotfile... "
# TODO submodules don't play well with ls-files? I want each file, not the submodule, to be inspected...
for FILE in $(git ls-files | grep "^\."); do
  REPO_FILE="$REPO/$FILE"
  MACHINE_FILE="$HOME/$FILE"

  # if the files aren't different, continue
  if diff "$REPO_FILE" "$MACHINE_FILE" &> /dev/null; then
    continue
  fi

  # '-nt' means "newer than". Don't backup the repo file manually cuz we use git
  if [ $REPO_FILE -nt $MACHINE_FILE ]; then
    [ -z "$CHANGED" ] && printf "\n"; CHANGED=1
    backup $MACHINE_FILE $REPO_FILE
    # TODO maybe I should be using rsync here..
    cp $REPO_FILE $MACHINE_FILE
  else
    printf "  repo's $FILE has been updated\n"
    cp $MACHINE_FILE $REPO_FILE
  fi
done

echo "done."
