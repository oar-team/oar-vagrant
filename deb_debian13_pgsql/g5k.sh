#!/bin/bash -x
set -e

SERVER=$(host $1 | sed -ne 's/^.*\s\([[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\)$/\1/p')
FRONTEND=$(host $2 | sed -ne 's/^.*\s\([[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\)$/\1/p')
NODE=$(host $3 | sed -ne 's/^.*\s\([[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\)$/\1/p')

IP=($(ip r | sed -ne 's/^\([[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\)\.[[:digit:]]\+\/\([[:digit:]]\+\)\s.*$/\1 \2/p'))
PREFIX=${IP[0]}
MASK=${IP[1]}

ssh root@$SERVER "echo -e 'host *\nStrictHostKeyChecking no' > ~/.ssh/config"
scp ~/.ssh/id_rsa* root@$SERVER:.ssh/
ssh root@$SERVER 'apt-get update && apt-get -y install iptables jq'
rsync -avz . root@$SERVER:/vagrant
ssh root@$SERVER /vagrant/provision.sh server $PREFIX $MASK $SERVER $FRONTEND no 0 oar-ftp.imag.fr

ssh root@$FRONTEND "echo -e 'host *\nStrictHostKeyChecking no' > ~/.ssh/config"
scp ~/.ssh/id_rsa* root@$FRONTEND:.ssh/
rsync -avz . root@$FRONTEND:/vagrant
ssh root@$FRONTEND /vagrant/provision.sh frontend $PREFIX $MASK $SERVER $FRONTEND no 0 oar-ftp.imag.fr

ssh root@$NODE "echo -e 'host *\nStrictHostKeyChecking no' > ~/.ssh/config"
scp ~/.ssh/id_rsa* root@$NODE:.ssh/
ssh root@$SERVER 'apt-get update && apt-get -y install hwloc-nox'
rsync -avz . root@$NODE:/vagrant
ssh root@$NODE /vagrant/provision.sh nodes $PREFIX $MASK $SERVER $FRONTEND no 0 oar-ftp.imag.fr
