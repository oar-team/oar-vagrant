#!/bin/bash -x
set -e

SERVER=$1
FRONTEND=$2

IP=($(ip -br a | sed -ne 's/^eth.*\s\([[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\)\.[[:digit:]]\+\/\([[:digit:]]\+\)\s.*$/\1 \2/p'))
PREFIX=${IP[0]}
MASK=${IP[1]}

cat ssh/id_rsa.pub ~/.ssh/authorized_keys > ssh/authorized_keys
rsync -avz . root@$SERVER:/vagrant
rsync -rvz ssh/* root@$SERVER:/root/.ssh/
ssh root@$SERVER 'apt-get update && apt-get -y install iptables jq'
ssh root@$SERVER /vagrant/provision.sh server $PREFIX $MASK $SERVER $FRONTEND no 1 oar-ftp.imag.fr

rsync -avz . root@$FRONTEND:/vagrant
rsync -rvz ssh/* root@$FRONTEND:/root/.ssh/
ssh root@$FRONTEND 'apt-get update && apt-get -y install iptables jq'
ssh root@$FRONTEND /vagrant/provision.sh frontend $PREFIX $MASK $SERVER $FRONTEND no 1 oar-ftp.imag.fr
