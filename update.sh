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
echo "Updating each dotfile"
######### For every dotfile in the repo (do not recurse into folders) ##########
for file in $(ls -A1 | grep "^\."); do
  if [[ $file == *.sw[klmnop] ]] || [[ $file == .git ]]; then
    continue
  fi

  OLD_FILE="$HOME"/"$file"
  NEW_FILE="$(pwd)"/"$file"

  ############################## special cases ################################
  if  [[ $file == .local ]]; then
    NEW_FILE="$NEW_FILE"/bin
    OLD_FILE="$HOME"/"$file"/bin
  fi

  if  [[ $file == .ssh ]]; then
    NEW_FILE="$NEW_FILE"/config
    OLD_FILE="$HOME"/"$file"/config
  fi
  ############################## special cases ################################

  if [ -L "$OLD_FILE" ]; then
    echo "$OLD_FILE is a symlink, updating it"
    rm "$OLD_FILE"
    ln -s "$NEW_FILE" "$OLD_FILE"
    continue
  fi

  if [ $INTERACTIVE = true ] ; then
    # If interactive, ask for user input along the way
    if [ -f "$OLD_FILE" || -d "$OLD_FILE" ]; then
      echo ""
      echo "$OLD_FILE already exists."
      read -p "Move it to /tmp and symlink in $file? [y/n] > " -n 1 CONFIRM
      if [[ "$CONFIRM" == [Yy] ]]; then
        backup "$OLD_FILE"
        ln -s "$NEW_FILE" "$OLD_FILE"
      fi
    else
      echo "$OLD_FILE doesn't exist."
      read -p "Create link to $file? [y/n] > " -n 1 CONFIRM
      if [[ "$CONFIRM" == [Yy] ]]; then
        ln -s "$NEW_FILE" "$OLD_FILE"
      fi
    fi
  else
    #non-interactive
    if [ -f "$OLD_FILE" || -d "$OLD_FILE" ]; then
      backup "$OLD_FILE"
    fi
    ln -s "$NEW_FILE" "$OLD_FILE"
  fi
done

echo "done."
