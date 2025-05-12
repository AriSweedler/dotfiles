export NVS_HOME="${HOME}/.nvs"
function nvs-setup() {
  [ -s "${NVS_HOME}/nvs.sh" ] && . "${NVS_HOME}/nvs.sh"
  nvs auto on
}
 
node_switch() {
  if [ -f './nodeSwitch.sh' ]; then
    . ./nodeSwitch.sh $@
  else
    $(npm bin)/$@
  fi
}
 
 
alias gulp="node_switch gulp"
alias npr="node_switch npm run"
