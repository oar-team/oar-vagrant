#!/bin/bash 
ACTION=$1
SNAP_STAMP=$2
VMNAME_PREFIX=${PWD##*/}
if [ -z "$1" ]; then
  echo "No action given" >&2
  exit 1
fi
case $ACTION in
    snap*)
      echo "Snapshoting with stamp: ${SNAP_STAMP:=$(date +%F_%T)}"
      for vm in $(vboxmanage list vms | grep -e "^\"${VMNAME_PREFIX}_[^\"]\+\"" | sed 's/^"\([^"]\+\)" {\(.\+\)}$/\1:\2/'); do
        echo -n "Snapshoting ${vm%:*} > "
        vboxmanage snapshot ${vm#*:} take $SNAP_STAMP
      done
      ;;
    restore*)
      echo "Try to restore snapshot with stamp: $SNAP_STAMP"
      for vm in $(vboxmanage list vms | grep -e "^\"${VMNAME_PREFIX}_[^\"]\+\"" | sed 's/^"\([^"]\+\)" {\(.\+\)}$/\1:\2/'); do
        echo -n "Pausing VM ${vm%:*} > "
        vboxmanage controlvm ${vm#*:} savestate
        echo "Restoring snapshot"
        vboxmanage snapshot ${vm#*:} restore $SNAP_STAMP
        echo -n "Resuming VM > "
        vboxmanage startvm ${vm#*:} --type headless
      done
      ;;
    list*)
      for vm in $(vboxmanage list vms | grep -e "^\"${VMNAME_PREFIX}_[^\"]\+\"" | sed 's/^"\([^"]\+\)" {\(.\+\)}$/\1:\2/'); do
        echo "Listing snapshots of ${vm%:*}:"
        vboxmanage snapshot ${vm#*:} list
      done
      ;;
    del*)
      echo "Delete snapshots with stamp: $SNAP_STAMP"
      for vm in $(vboxmanage list vms | grep -e "^\"${VMNAME_PREFIX}_[^\"]\+\"" | sed 's/^"\([^"]\+\)" {\(.\+\)}$/\1:\2/'); do
        echo -n "Delete snapshots for vm ${vm%:*}:"
        vboxmanage snapshot ${vm#*:} delete $SNAP_STAMP
      done
      ;;
    \?)
      echo "Invalid action: $ACTION" >&2
      exho 1
      ;;
esac

