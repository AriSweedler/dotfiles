#!/bin/bash

ANIMAL=$(cowsay -l | tr -s ' ' '\n' | tail -$(jot -r 1 1 50) | head -1)
cowsay -f $ANIMAL $(fortune)
