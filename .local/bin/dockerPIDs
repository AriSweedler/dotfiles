#! /bin/bash

# Output the PID of all docker containers running on your machine

################################ Global values ################################
# DC_IDs: String - Docker Container _ ID                                      #
#     Docker ID of each docker container running on this machine              #
# C_PIDs: String - Container _ PID                                            #
#     Process ID of a docker container.                                       #
###############################################################################

getAllDockerContainerIDs() {
  DC_IDs=`docker container ls \
        | awk '{print $1}' \
        | tr '\n' ' ' \
        | cut -d ' ' -f 2- `
}

getPIDfromDockerContainerID() {
  TEMP=`docker inspect $1 \
        | grep 'Pid\>' \
        | awk '{print $2}' `
  PID=${TEMP%,} # bash substitution, % means "remove suffix". Suffix is ",".
}

getContainerProcessIDs() {
  C_PIDs=''
  getAllDockerContainerIDs
  for ID in $DC_IDs
  do
    getPIDfromDockerContainerID $ID
    C_PIDs="$C_PIDs $PID"
  done
}

getContainerProcessIDs
echo "$C_PIDs"
