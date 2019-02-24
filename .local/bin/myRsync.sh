#!/bin/bash

# specify host
HOST="ucla"

# excludes
FLAGS="-av"
EXCLUDE=(*.o .*.swp *.vcxproj* *.dbg)
for ex in ${EXCLUDE[@]}
do
  FLAGS="$FLAGS --exclude=$ex"
done

src="$HOME/Desktop/"
dest="${HOST}:~/Classes/CS-117/"
item="hw1/"

src+="$item"
dest+="`dirname $item`"

echo "rsync   $FLAGS"
echo "FROM:   ${src}"
echo "TO:     ${dest}"

rsync $FLAGS ${src} ${dest}
