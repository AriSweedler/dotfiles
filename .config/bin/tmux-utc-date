#!/bin/bash
local_day=$(date +%d)
utc=$(TZ=UTC date '+%d %H:%M')
[ "$local_day" != "${utc%% *}" ] && printf "+1d "
echo "${utc#* }"
