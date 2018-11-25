#!/usr/bin/env bash

# script to check all the dotfiles in this directory with all the dotfiles on
# my machine. If these files are newer, then update the files on this machine.

################################### settings ###################################
# this is where the repo should be. I'm standardizing it across all machines -
# but I could also execute `find ~ -name "dotfiles"` or something like that
REPO="$HOME/dotfiles"
# Here're the dotfiles I care about
FILES=(.bash_aliases .bash_prompt .bashrc .gitconfig .inputrc .vimrc)
#FOLDERS=(.vim .ssh)

############################### backup function ################################
function backup() {
  if [ ! -f $1 ]; then
    echo "file $1 cannot be backed up because it doesn't exist"
    return 1
  fi
  TIME=$(stat -lt "%Y%m%d%H%M%S" $1 | awk '{print $6}')
  BACKUP=/tmp/${TIME}-$(basename ${1})
  cp $1 $BACKUP
  echo "  backup stored at $BACKUP"
}

######## if we don't have the repo, then there's no point in continuing ########
# TODO git pull if needed
if [ ! -d "$REPO/.git" ]; then
  REPO="$HOME/GitHub/machine/dotfiles"
  if [ ! -d "$REPO/.git" ]; then
    echo "No repo found. Please git clone git@github.com:AriSweedler/dotfiles.git"
    exit 1
  fi
fi

# TODO populate FILES array from files in the REPO instead of a static array.
for FILE in ${FILES[*]}; do
  REPO_FILE="$REPO/$FILE"
  MACHINE_FILE="$HOME/$FILE"

  # if the files aren't different, continue
  if diff -q "$REPO_FILE" "$MACHINE_FILE"; then
    continue
  fi

  if [ $REPO_FILE -nt $MACHINE_FILE ]; then
    # if the REPO_FILE is newer, than MACHINE_FILE is outta date. Backup
    # machine file then overwrite machine file
    echo "machine's $FILE is outta date. Making a backup and updating machine's file"
    backup $MACHINE_FILE
    cp $REPO_FILE $MACHINE_FILE
  else
    # if the MACHINE_FILE is newer, than REPO_FILE is outta date. Overwrite
    # repo file. Don't need to backup repo file, cuz that's what git is for!
    echo "repo's $FILE is outta date - updating it. (Make sure you've pulled all changed. Commit these ones)"
    cp $MACHINE_FILE $REPO_FILE
  fi
done

echo "dotfiles are up to date"
