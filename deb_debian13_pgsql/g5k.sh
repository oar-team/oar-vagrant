#!/bin/bash
# Script to do the equivalent of vagrant up on Grid5000, provisioning 3 nodes.
#
# On a Grid'5000 frontend:
# 1. reserve and deploy 3 nodes with debian:
# $ grd bootstrap -r now -e debiantesting-min -l /host=3
# 2. trigger the provisioning (g5k.sh calls provisioning.sh, same as vagrant)
# $ ./g5k.sh dahu-12 dahu-23 dahu-32
# or if OARNODE_FILE exists, just
# $ ./g5k.sh

CMD=$0

set -e
usage() {
	cat <<EOF
Usage:
  ${CMD##*/} <SERVER> <FRONTEND> <NODE> [<NODE> ...]
hostnames of server, frontend and nodes are provided in command line.

  ${CMD##*/} <FILE>
hostnames of server, frontend and nodes are provided in FILE (1 per line)
  
  ${CMD##*/}
hostnames of server, frontend and nodes are provided in $OAR_NODEFILE.

EOF
}

if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    usage
    exit 0
fi

nodefile() {
	  if [ -r "$1" ]; then
        mapfile -t NODES < <(uniq "$1")
    else
        usage 1>&2
        exit 1
    fi
}

if [ $# -ge 3 ]; then
    NODES=( "$@" )
elif [ -n "$1" ]; then
    nodefile "$1"
elif [ -n "$OAR_NODEFILE" ]; then
    nodefile  "$OAR_NODEFILE"
fi

if [ ${#NODES[*]} -lt 3 ]; then
    usage 1>&2
    exit 1
fi

mapfile -t IP < <(ip r | sed -ne 's/^\([[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\)\.[[:digit:]]\+\/\([[:digit:]]\+\)\s.*$/\1\n\2/p')
PREFIX=${IP[0]}
MASK=${IP[1]}

SERVER=$(host "${NODES[0]}" | sed -ne 's/^.*\s\([[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\)$/\1/p')
FRONTEND=$(host "${NODES[1]}" | sed -ne 's/^.*\s\([[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\)$/\1/p')

cat <<EOF
Setup OAR cluster on:
- SERVER: ${NODES[0]} ($SERVER)
- FRONTEND: ${NODES[1]} ($FRONTEND)
- NODES: ${NODES[*]:2}
- PREFIX/MASK: ${IP[0]}/${IP[1]}

Starting in 2 secs... (hit Ctrl-C now to stop!)
EOF
sleep 2

prepare() {
    ssh root@"$1" "echo -e 'host *\nStrictHostKeyChecking no' > ~/.ssh/config"
    scp ~/.ssh/id_rsa* root@"$1":.ssh/
    ssh root@"$1" 'apt-get update && apt-get -y install apt iptables jq rsync bash-completion vim-nox hwloc-nox' &
    rsync -avz ${CMD%/*}/. root@"$1":/vagrant
}

server() {
    ssh root@"$SERVER" /vagrant/provision.sh server "$PREFIX" "$MASK" "$SERVER" "$FRONTEND" no 0 oar-ftp.imag.fr sid_beta
    printf "%s\n" "${NODES[@]:2}" | ssh root@"$SERVER" 'cat > /tmp/nodes'
}

frontend() {
    ssh root@"$FRONTEND" /vagrant/provision.sh frontend "$PREFIX" "$MASK" "$SERVER" "$FRONTEND" no 0 oar-ftp.imag.fr sid_beta
}

node() {
    ssh root@"$1" /vagrant/provision.sh nodes "$PREFIX" "$MASK" "$SERVER" "$FRONTEND" no 0 oar-ftp.imag.fr sid_beta
}

for n in "${NODES[@]}"; do
    prepare $n | sed "s/^/[PREPARE:$n] /" &
done
wait

server | sed "s/^/[SERVER:${NODES[0]}] /"
frontend | sed "s/^/[FRONTEND:${NODES[1]}] /"

if [ ${#NODES[*]} -le 3 ]; then
    node "${NODES[2]}" | sed "s/^/[NODE:${NODES[2]}] /"
else
    for n in "${NODES[@]:2}"; do
       node "$n" | sed "s/^/[NODE:$n] /" &
    done
    wait
fi

cat <<EOF

Provisoning is done.

You may now register nodes in the OAR database, using a command such as:
$ ssh root@${NODES[0]} "oar_resources_init -v -y -x /tmp/nodes"

EOF
