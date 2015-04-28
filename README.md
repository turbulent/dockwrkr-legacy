# dockwrkr
General purposes docker-compose shell(bash) wrapper script.  

# Overview

dockwrkr is a simple bash shell script that acts as a wrapper when hooking docker-compose into your process manager.
What dockwrkr adds is the ability for writing PID files of the started containers (for monitoring purposes) as well
as provide a series of simple command to interrogate the docker daemon about container status for your docker-compose services.

Particularely useful when hooking into upstart and other process manager.

# Usage 

Simply make sure dockwrkr.sh is in the same directory as your fig/docker-compose.yml config file.

```
Usage: dockwrkr.sh COMMAND [options] [SERVICE] [ARGS...]

dockwrkr - Docker compose wrapper.

Options:
  -r    Remove the container of the service when stopping.

Commands:
  start   Start the specified compose service
  stop    Stop the specified compose service
  status        Output current status for all defined scompose service
  stats         Output live docker status for all compose services
  reset   Stop all running services and remove every service container.
  exec    Exec a command on a service.
```
 
## status

Returns a table with the PID and UPTIME/EXIT status of the docker-compose services. The program will do the service to container name lookup itself.

Sample output:
```
NAME             CONTAINER     UP   PID    IP           UPTIME/EXIT
web              6240e4dc4eaa  yes  22796  172.17.0.22  21 minutes and 9 seconds
db               a661c68a679e  yes  21814  172.17.0.15  21 minutes and 19 seconds
cache            cecb80cd1135  -    -      -            SIGKILL received
sessions         fb8a00b8e7ec  yes  22079  172.17.0.17  21 minutes and 16 seconds
redis            07babfbd88cc  -    -      -
qmgr             754fa1dd0f82  yes  22309  172.17.0.19  21 minutes and 15 seconds
workers          3721d5595256  yes  22426  172.17.0.20  21 minutes and 14 seconds
rabbit           a2b9c4224f19  yes  22608  172.17.0.21  21 minutes and 12 seconds
```

## start / stop

These commands will start or stop the specified docker-compose service. Note that this program is designed to work on the service one by one. When a service has been started, the docker daemon is interrogated for the PID of the container process, it is then written in /var/run/docker/$SERVICE.pid.

When a service is stopped, the PID file approprietely cleared.

Stopping with the -r option will also remove the container.

## stats

The program will fetch the running docker-compose services and their associated containers and launch a "docker stats" stream in your terminal.
```
CONTAINER           CPU %               MEM USAGE/LIMIT       MEM %               NET I/O
vol_cache_1         0.00%               0 B/0 B               0.00%               0 B/0 B
vol_db_1            0.12%               228.4 MiB/3.615 GiB   6.17%               630.7 KiB/285.5 KiB
vol_qmgr_1          0.04%               110.3 MiB/3.615 GiB   2.98%               289.1 KiB/626.1 KiB
vol_rabbit_1        0.15%               101.1 MiB/3.615 GiB   2.73%               112.3 KiB/517.3 KiB
vol_redis_1         0.00%               0 B/0 B               0.00%               0 B/0 B
vol_sessions_1      0.00%               6.203 MiB/3.615 GiB   0.17%               4.52 KiB/648 B
vol_web_1           0.05%               60.69 MiB/3.615 GiB   1.64%               77.52 KiB/126.1 KiB
vol_workers_1       0.02%               108.3 MiB/3.615 GiB   2.93%               15.58 KiB/10.36 KiB
```

# exec

You can use *dockwrkr exec myservice mycommand* to basically perform a "docker exec" on the named service. Dockwrkr will do the docker-compose service to docker container name lookup for you.

Example:
```
dockwrkr.sh exec myservice ps -auxwww
```

This obviously can be used to enter the service/container in one go:

```
#host $ dockwrkr.sh exec myservice /bin/bash
#container $  exit
#host $
```

## reset

This command will simply stop and remove all service containers.

# dockwrkr with upstart

Provided you have dockwrkr and your docker-compose.yml file in /vol you will need one upstart job file per service you want to hook. The job will simply instruct dockwrkr to start the docker-compose service "myservice":

/etc/init/myservice.conf: 
```
#!upstart
stop on runlevel [06]

chdir /vol
pre-start script
  /vol/dockwrkr.sh start myservice
end script

post-stop script
  /vol/dockwrkr.sh stop myservice
end script
```

You can then use *start myservice* and *stop myservice* on your Ubuntu system to control this service.

## Multiple services

You can also use a linked job to start / stop multiple docker-compose service on host boot / shutdown.
Templating this file with salt/ansible/chef makes this deployment simple for DevOps.

Suppose you have a docker-compose file with 3 services : web, db and cache, you could create a master upstart job like so:
```
#!upstart
description     "Host LXC Containers"

start on (filesystem and started docker and net-device-up IFACE!=lo)
stop on runlevel [!2345]

chdir /vol
pre-start script
start db || :
start cache || :
start web || :
end script

post-stop script
stop db || :
stop cache || :
stop web || :
end script
```

This would start the *db, cache, web* docker-compose service on host boot.

