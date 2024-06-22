function displayplacer::laptop::monitor_on_stand() {
  displayplacer "id:06C4F340-690B-F04C-267B-E35CF60D55F0 res:1792x1120 hz:59 color_depth:8 scaling:on origin:(0,0) degree:0" "id:$(displayplacer::second_screen) res:2560x1440 hz:60 color_depth:8 scaling:off origin:(1792,-1400) degree:0"
}

built_in_screen_id="06C4F340-690B-F04C-267B-E35CF60D55F0"
function displayplacer::second_screen() {
  displayplacer list | grep 'Persistent screen id' | grep -v "$built_in_screen_id" | awk -F':' '{print $2}' | tr -d ' '
}
