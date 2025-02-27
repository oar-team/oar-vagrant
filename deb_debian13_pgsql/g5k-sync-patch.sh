#!/bin/bash

set -e

nodefile() {
	  if [ -r "$1" ]; then
        mapfile -t NODES < <(uniq "$1")
    else
        echo "Error"
        exit 1
    fi
}

if [ -n "$1" -a ! -r "$1" ]; then
    NODES=( "$@" )
elif [ -n "$1" ]; then
    nodefile "$1"
elif [ -n "$OAR_NODEFILE" ]; then
    nodefile  "$OAR_NODEFILE"
fi

if [ ! -n "${NODES[*]}" ]; then
    echo "Error"
    exit 1
fi

for n in "${NODES[@]}"; do
    echo "# Sync $n"
    rsync -avz --delete ${0%/*}/patch root@$n:/vagrant/
		echo
done
