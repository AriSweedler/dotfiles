#!/usr/bin/env bash

SCRIPT=$(basename "$0")

############################### backup function ################################
#TODO make a tmpdir for each invocation
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
  mv $ORIGINAL $BACKUP
}

################################ usage function ################################
function usage() {
  echo "Usage: $SCRIPT [--interactive]"
  echo "   symlinks all dotfiles in this repo to your home directory."
  echo "   saves current dotfiles to /tmp"
  exit 1
}

################################ parse options ################################
INTERACTIVE=false
FORCE=false
while [[ $# -gt 0 ]]; do
  case $1 in
    "-i"|"--interactive") INTERACTIVE=true;;
    *) echo "unknown argument, $1"; usage;;
  esac
  shift
done

############################### Begin script body ##############################
####### for every dotfile in the repo (including stuff like '.vim/file') #######
echo "Updating each dotfile"
for file in $(git ls-files); do
  echo  "~~"
  # Don't place the script or the readme into our home dir
  if [[ $file == $SCRIPT ]] ; then
    continue
  fi

  # If interactive, ask for user input along the way
  OLD_FILE="$HOME"/"$file"
  NEW_FILE="$(pwd)"/"$file"

  if [ $INTERACTIVE = true ] ; then
    #interactive
    if [ -f $OLD_FILE ]; then
      echo "$OLD_FILE already exists."
      read -p "Move it to /tmp and symlink in $file? [y/n] > " -n 1 CONFIRM
      if [[ $CONFIRM == [Yy] ]]; then
        backup $OLD_FILE
        echo "ln -s $NEW_FILE $OLD_FILE"
      fi
    else
      echo "$OLD_FILE doesn't exist."
      read -p "Create link to $file? [y/n] > " -n 1 CONFIRM
      if [[ $CONFIRM == [Yy] ]]; then
        echo "ln -s $NEW_FILE $OLD_FILE"
      fi
    fi
  else
    #non-interactive
    if [ -f $OLD_FILE ]; then
      backup $OLD_FILE
    fi
    echo "ln -s $NEW_FILE $OLD_FILE"
  fi
done

echo "done."
