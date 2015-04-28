#!/bin/bash 

#Author: b@turbulent.ca

DWVERSION="0.8"
DOCKER=/usr/bin/docker
COMPOSE=/usr/local/bin/docker-compose
CONFFILE=docker-compose.yml
PIDBASE=/var/run/docker

SCRIPT=`basename ${BASH_SOURCE[0]}`

mkdir -p $PIDBASE

#Output live docker stats for all running services in compose
function cmd_srv_stats() {
  CONTAINERS=$($COMPOSE ps -q | xargs docker inspect -f '{{ .Name }}' | cut -c2-)
  exec $DOCKER stats $CONTAINERS
}

#Output a table of status for each define compose service
function cmd_srv_status() {
  srv_list

  format="%-16s %-13s %-4s %-6s %-12s %-50s\n"
  printf "$format" "NAME" "CONTAINER" "UP" "PID" "IP" "UPTIME/EXIT"

  for s in ${SERVICES} ; do
    CONTAINER=""
    srv_name $s
    if [ $CONTAINER ] ; then 
      lxc_status $CONTAINER
      if [ $RUNNING == "yes" ]; then 
        UPTIME=$(lxc_uptime $STARTEDAT) ; 
        printf "$format" "$s" "$CONTAINER" "$RUNNING" "$PID" "$IP" "$UPTIME" 
      else 
        UPTIME="-"  
        ERRLABEL=$(lxc_errorlabel $EXITCODE "$ERROR")
        printf "$format" "$s" "$CONTAINER" "$RUNNING" "$PID" "$IP" "$ERRLABEL" 
      fi
    else
      printf "$format" "$s" "-" "-" "-" "-" "-" 
    fi 
  done
}

#Exec on a service
function cmd_srv_exec() {
  SERVICE=$1
  COMMAND=$2
  if [ -z $SERVICE ]; then echo "ERROR - Please provide a service to exec" && return 1 ; fi

  srv_name $SERVICE
  if [ -z $CONTAINER ]; then
    echo "ERROR - Service ${SERVICE} has no container created."
    return 1
  fi

  lxc_ghosted $CONTAINER
  lxc_running $CONTAINER
  if [ $? -ne 1 ]; then
    echo "ERROR - service ${SERVICE} is not running."
    return 1
  fi

  exec $DOCKER exec -t -i ${CONTAINER} $COMMAND
}

#Start a compose service
function cmd_srv_start() {
  SERVICE=$1
 
  if [ -z $SERVICE ]; then echo "ERROR - Please provide a service to start." && return 1 ; fi

  srv_name $SERVICE
  if [ -z $CONTAINER ]; then
    $COMPOSE up -d $SERVICE
    if [ $? -ne 0 ]; then
      echo "ERROR - Failed to start service ${SERVICE}."
      return 1
    fi
  else
    lxc_ghosted $CONTAINER
    lxc_running $CONTAINER
    if [ $? -eq 1 ]; then
      echo "ERROR - service ${SERVICE} is already running."
      return 1
    else
      $COMPOSE start ${SERVICE}
      if [ $? -ne 0 ]; then
        echo "ERROR - Failed to start ${SERVICE} (lxc: ${CONTAINER})"
        return 1 
      fi
    fi
  fi

  srv_name $SERVICE
  lxc_pid $CONTAINER
  echo $PID > $PIDFILE
  echo "OK - service ${SERVICE} has been started. (pid: $PID)"
}

#Stop a compose service
function cmd_srv_stop() {
  SERVICE=$1
  if [ -z $SERVICE ]; then echo "ERROR - Please provide a service to stop." && return 1 ; fi
  srv_name $SERVICE
  if [ -z $CONTAINER ]; then
    echo "ERROR - service ${SERVICE} : container does not exist."
    return 1
  else
    lxc_ghosted $CONTAINER
    lxc_running $CONTAINER
    if [ $? -eq 1 ]; then
      $COMPOSE stop ${SERVICE}
      if [ $? -ne 0 ]; then
        echo "ERROR - Failed to stop service ${SERVICE} (lxc: ${CONTAINER})"
        return 1
      else
        echo "OK - service ${SERVICE} (lxc: ${CONTAINER}) has been stopped."
      fi
    else
      echo "OK - service ${SERVICE} (lxc: ${CONTAINER}) is not running."
    fi
  fi

  rm -f $PIDFILE
}

#Remove a compose service lxc
function cmd_srv_rm() {
  SERVICE=$1
  if [ -z $SERVICE ]; then echo "ERROR - Please provide a service to remove." && return 1 ; fi
  srv_name $SERVICE
  if [ -z $CONTAINER ]; then
    echo "OK - service ${SERVICE} : lxc does not exist."
    return 0 
  fi

  lxc_ghosted $CONTAINER
  lxc_running $CONTAINER
  if [ $? -eq 1 ]; then
    cmd_srv_stop $SERVICE
  fi

  $COMPOSE rm -f ${SERVICE}
  if [ $? -ne 0 ]; then
    echo "ERROR - service ${SERVICE} : failed to remove lxc ${CONTAINER}"
    return 1
  fi
}

#Stop and delete all service and containers
function cmd_srv_reset() {
  $COMPOSE stop
  if [ $? -ne 0 ]; then
    echo "ERROR - Failure to stop running containers."
    return 1
  fi

  $COMPOSE rm -f
  if [ $? -ne 0 ]; then
    echo "ERROR - Failure to erase stopped containers."
    return 1
  fi

  echo "OK - All services stopped, all containers removed."
}

function lxc_rm() {
  CONTAINER=$1

  lxc_exists $CONTAINER
  if [ $? -eq 1 ]; then
    lxc_ghosted $CONTAINER

    lxc_running $CONTAINER
    if [ $? -eq 1 ]; then
      echo "Stopping lxc '$CONTAINER' ..."
      $DOCKER stop $CONTAINER
      if [ $? -ne 0 ]; then
        echo "Failed to stop lxc '$CONTAINER'"
        return 1
      fi
    fi

    echo "Removing lxc '$CONTAINER' ..."
    $DOCKER rm $CONTAINER

    if [ $? -ne 0 ]; then
      echo "Failed to remove lxc '$CONTAINER'"
      return 1
    fi

    lxc_clearpid $CONTAINER

  else
    echo "WARNING - lxc '$CONTAINER' does not exist."
  fi
}

#Get a list of services defined in the compose config
function srv_list() {
  SERVICES=$(grep "^[A-Za-z0-9]*:$" $CONFFILE | cut -d":" -f1)
}

#Query compose for the name of the container for $SERVICE
function srv_name() {
  SERVICE=$1
  CONTAINER=$($COMPOSE ps -q $SERVICE)
  CONTAINER="${CONTAINER:0:12}"
  PIDFILE=${PIDBASE}/${SERVICE}.pid
}


function lxc_exists() {
  CONTAINER=$1
  STATE=$($DOCKER inspect --format="{{ .State.Running }}" $CONTAINER 2> /dev/null)
  if [ $? -eq 1 ]; then
    return 0
  fi
  return 1
}

function lxc_running() {
  CONTAINER=$1
  RUNNING=$($DOCKER inspect --format="{{ .State.Running }}" $CONTAINER 2> /dev/null)
  if [ $? -eq 1 ]; then
    echo "WARNING - lxc '$CONTAINER' does not exist."
    return 0
  fi
  if [ "$RUNNING" == "false" ]; then
    return 0
  fi
  return 1
}

function lxc_ghosted() {
  CONTAINER=$1
  GHOST=$($DOCKER inspect --format="{{ .State.Ghost }}" $CONTAINER)
  if [ "$GHOST" == "true" ]; then
    echo "WARNING - lxc '$CONTAINER' has been ghosted."
    return 1
  fi
  return 0
}

function lxc_start() {
  CONTAINER=$1
  
  lxc_exists $CONTAINER
  if [ $? -eq 1 ]; then
    lxc_ghosted $CONTAINER
    lxc_running $CONTAINER
    if [ $? -eq 1 ]; then
      echo "WARNING - lxc '$CONTAINER' is already running."
    else 
      echo "Starting lxc '$CONTAINER' ..." 
      $DOCKER start $CONTAINER
      if [ $? -ne 0 ]; then
        echo "Failed to start lxc '$CONTAINER'"
        return 1
      fi
    fi
  else
    echo "ERROR - lxc ${CONTAINER} does not exist."
    return 1
  fi 
}

function lxc_stop() {
  CONTAINER=$1
  
  lxc_exists $CONTAINER
  if [ $? -eq 1 ]; then
    lxc_ghosted $CONTAINER
    lxc_running $CONTAINER
    if [ $? -eq 1 ]; then
      echo "Stopping lxc '$CONTAINER' ..."
      $DOCKER stop $CONTAINER
      if [ $? -ne 0 ]; then
        echo "Failed to remove lxc '$CONTAINER'"
        return 1
      fi
    else  
      echo "WARNING - lxc '$CONTAINER' is not running."
    fi
  else
    echo "WARNING - lxc '$CONTAINER' does not exist."
  fi 

  lxc_clearpid $CONTAINER
}

function lxc_clearpid() {
  CONTAINER=$1
  if [ -f /var/run/lxc-$CONTAINER.pid ]; then
    rm -f /var/run/lxc-$CONTAINER.pid
  fi
}

function lxc_rm() {
  CONTAINER=$1
  
  lxc_exists $CONTAINER
  if [ $? -eq 1 ]; then
    lxc_ghosted $CONTAINER

    lxc_running $CONTAINER
    if [ $? -eq 1 ]; then
      echo "Stopping lxc '$CONTAINER' ..."
      $DOCKER stop $CONTAINER
      if [ $? -ne 0 ]; then
        echo "Failed to stop lxc '$CONTAINER'"
        return 1
      fi
    fi

    echo "Removing lxc '$CONTAINER' ..."
    $DOCKER rm $CONTAINER 

    if [ $? -ne 0 ]; then
      echo "Failed to remove lxc '$CONTAINER'"
      return 1
    fi

    lxc_clearpid $CONTAINER

  else
    echo "WARNING - lxc '$CONTAINER' does not exist."
  fi 
}

function lxc_pid() {
  CONTAINER=$1
  PID=$($DOCKER inspect --format '{{.State.Pid}}' $CONTAINER)
}

function lxc_errorlabel() {
  ERR=$1
  ERROR=$2
  case $1 in
  -1)
    echo "$ERROR" ;;
  1)
    echo "General error" ;;
  126) 
    echo "Command invoked cannot execute" ;;
  127)
    echo "Command not found" ;;
  137)
    echo "SIGKILL received" ;;
  143)
    echo "SIGTERM received" ;;
  0)
    echo "" ;;
  *)
    echo "Exit code $1"
  esac
}
 
function lxc_status() {
  CONTAINER=$1
  STATUS=$($DOCKER inspect -f '{{.Config.Image}}|{{.NetworkSettings.IPAddress}}|{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{$p}}->{{(index $conf 0).HostPort}}{{end}} {{end}}|{{.State.Pid}}|{{.State.StartedAt}}|{{.State.Running}}|{{.State.ExitCode}}|{{.State.Error}}' $CONTAINER)
  IMAGE=$(echo $STATUS | cut -d"|" -f 1)
  IP=$(echo $STATUS | cut -d"|" -f 2)
  if [ -z $IP ]; then IP="-" ; fi
  PORTS=$(echo $STATUS | cut -d"|" -f 3)
  PID=$(echo $STATUS | cut -d"|" -f 4)
  if [ -n $PID ] && [ $PID -eq 0 ]; then PID="-" ; fi
  STARTEDAT=$(echo $STATUS | cut -d"|" -f 5)
  RUNNING=$(echo $STATUS | cut -d"|" -f 6)
  if [ $RUNNING == "true" ]; then RUNNING="yes" ; else RUNNING="-" ; fi
  EXITCODE=$(echo $STATUS | cut -d"|" -f 7)
  ERROR=$(echo $STATUS | cut -d"|" -f 8)
}

function lxc_inspect_ports() {
  CONTAINER=$1
  echo $($DOCKER inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}}->{{(index $conf 0).HostPort}} {{end}}' $CONTAINER)
}

function lxc_inspect() {
  CONTAINER=$1
  FILTER=$2
  echo $($DOCKER inspect -f "${FILTER}" $CONTAINER)
}

function lxc_uptime() {
  local DATE=$1
  local START=$(date '+%s' -d "$( echo $DATE | sed -r 's/(.*)T(..):(..):(..)/\1 \2:\3:\4/')")
  local NOW=$(date '+%s')
  local T=$(($NOW - $START))
  local D=$((T/60/60/24))
  local H=$((T/60/60%24))
  local M=$((T/60%60))
  local S=$((T%60))
  if [[ $D > 0 ]]; then
    [[ $D > 0 ]] && printf '%d days ' $D 
    [[ $H > 0 ]] && printf '%d hours ' $H
  else
    [[ $M > 0 ]] && printf '%d minutes ' $M
    [[ $D > 0 || $H > 0 || $M > 0 ]] && printf 'and '
    printf '%d seconds\n' $S
  fi
}


function parse_args() {

  CMD=$1
  shift
  
  while getopts "r" opt; do
    declare "OPT_$opt=${OPTARG:-1}"
    shift
  done
 
  REMOVE=$OPT_r 
  CONTAINER=$1
  shift
 
  ARG="$@"

  USAGE=$(
cat << HERE
Usage: ${SCRIPT} COMMAND [options] [SERVICE] [ARGS...]

dockwrkr - Docker compose wrapper. (v$DWVERSION)


Options:
  -r		Remove the container of the service when stopping.

Commands:
  start		Start the specified compose service
  stop		Stop the specified compose service
  status        Output current status for all defined scompose service
  stats         Output live docker status for all compose services
  reset		Stop all running services and remove every service container.
  exec		Exec a command on a service.

HERE
)
 
  if [ -z $CMD ]; then
    echo "$USAGE"
    echo
    echo "Please specify a command."
    echo
    exit 1
  fi
}

parse_args "$@"

case $CMD in
  help) echo "$USAGE" && echo && echo ;;
  stats) cmd_srv_stats ;;
  status) cmd_srv_status ;;
  start) cmd_srv_start $CONTAINER ;;
  stop)
    if [ $REMOVE ]; then cmd_srv_rm $CONTAINER 
    else cmd_srv_stop $CONTAINER ; fi
    ;;
  reset) cmd_srv_reset ;;
  exec) cmd_srv_exec $CONTAINER "$ARG" ;;
esac

exit $?

