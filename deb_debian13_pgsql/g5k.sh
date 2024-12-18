#!/bin/bash -x
set -e

SERVER=$(host $1 | sed -ne 's/^.*\s\([[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\)$/\1/p')
FRONTEND=$(host $2 | sed -ne 's/^.*\s\([[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\)$/\1/p')
NODE=$(host $3 | sed -ne 's/^.*\s\([[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\)$/\1/p')

IP=($(ip r | sed -ne 's/^\([[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\)\.[[:digit:]]\+\/\([[:digit:]]\+\)\s.*$/\1 \2/p'))
PREFIX=${IP[0]}
MASK=${IP[1]}

#scp ~/public/oar/oar.list root@$SERVER:/etc/apt/sources.list.d/oar.list
ssh root@$SERVER "echo -e 'host *\nStrictHostKeyChecking no' > ~/.ssh/config"
scp ~/.ssh/id_rsa* root@$SERVER:.ssh/
ssh root@$SERVER 'apt-get update && apt-get -y install apt iptables jq rsync'
rsync -avz . root@$SERVER:/vagrant
ssh root@$SERVER /vagrant/provision.sh server $PREFIX $MASK $SERVER $FRONTEND no 0 oar-ftp.imag.fr sid_beta

#scp ~/public/oar/oar.list root@$FRONTEND:/etc/apt/sources.list.d/oar.list
ssh root@$FRONTEND "echo -e 'host *\nStrictHostKeyChecking no' > ~/.ssh/config"
scp ~/.ssh/id_rsa* root@$FRONTEND:.ssh/
ssh root@$SERVER 'apt-get update && apt-get -y install apt'
rsync -avz . root@$FRONTEND:/vagrant
ssh root@$FRONTEND /vagrant/provision.sh frontend $PREFIX $MASK $SERVER $FRONTEND no 0 oar-ftp.imag.fr sid_beta

#scp ~/public/oar/oar.list root@$NODE:/etc/apt/sources.list.d/oar.list
ssh root@$NODE "echo -e 'host *\nStrictHostKeyChecking no' > ~/.ssh/config"
scp ~/.ssh/id_rsa* root@$NODE:.ssh/
ssh root@$SERVER 'apt-get update && apt-get -y install apt hwloc-nox'
rsync -avz . root@$NODE:/vagrant
ssh root@$NODE /vagrant/provision.sh nodes $PREFIX $MASK $SERVER $FRONTEND no 0 oar-ftp.imag.fr sid_beta
