#!/bin/bash

set -e

export BOX=$1
export NETWORK_PREFIX=$2
export HOSTS_COUNT=$3
export OAR_FTP_HOST=$4
export OAR_FTP_DISTRIB=$5

if [ -z "$BOX" -o -z "$NETWORK_PREFIX" -o -z "$HOSTS_COUNT" -o -z "$OAR_FTP_HOST" ]; then
  echo "Error: syntax error, usage is $0 BOX NETWORK_PREFIX HOSTS_COUNT OAR_FTP_HOST [OAR_FTP_DISTRIB]" 1>&2
  exit 1
fi

stamp="provision etc hosts"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  echo ${NETWORK_PREFIX}.10 server >> /etc/hosts
  echo ${NETWORK_PREFIX}.11 frontend >> /etc/hosts
  for ((i=1;i<=$HOSTS_COUNT;i++)); do
    echo ${NETWORK_PREFIX}.$((100+i)) node-$i >> /etc/hosts
  done
  touch /tmp/stamp.${stamp// /_}
)

stamp="provision EPEL repo"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  rpm -Uvh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
  touch /tmp/stamp.${stamp// /_}
)

stamp="provision OAR ${OAR_FTP_DISTRIB:-stable} repo"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  cat <<EOF | tee /etc/yum.repos.d/OAR.repo
[OAR]
name=OAR
baseurl=http://$OAR_FTP_HOST/oar/2.5/rpm/centos6/${OAR_FTP_DISTRIB:-stable}/
gpgcheck=1
gpgkey=http://$OAR_FTP_HOST/oar/oarmaster.asc
enabled=0
EOF
  touch /tmp/stamp.${stamp// /_}
)

case $BOX in
  server)
    stamp="install and configure postgresql server"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      yum install -y postgresql-server
      service postgresql initdb
      PGSQL_CONFDIR=/var/lib/pgsql/data
      sed -i -e "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $PGSQL_CONFDIR/postgresql.conf
      sed -i -e "s/\(host \+all \+all \+127.0.0.1\/32 \+\)ident/\1md5/" \
             -e "s/\(host \+all \+all \+::1\/128 \+\)ident/\1md5/" $PGSQL_CONFDIR/pg_hba.conf
      cat <<EOF >> $PGSQL_CONFDIR/pg_hba.conf
#Access to OAR database
host oar all ${NETWORK_PREFIX}.0/24 md5
EOF
      chkconfig postgresql on
      service postgresql restart
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-server package"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      yum install -y --enablerepo=OAR oar-server oar-server-pgsql
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="set oar config"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      sed -i \
          -e 's/^\(DB_TYPE\)=.*/\1="Pg"/' \
          -e 's/^\(DB_HOSTNAME\)=.*/\1="server"/' \
          -e 's/^\(DB_PORT\)=.*/\1="5432"/' \
          -e 's/^\(DB_BASE_PASSWD\)=.*/\1="oar"/' \
          -e 's/^\(DB_BASE_LOGIN\)=.*/\1="oar"/' \
          -e 's/^\(DB_BASE_PASSWD_RO\)=.*/\1="oar_ro"/' \
          -e 's/^\(DB_BASE_LOGIN_RO\)=.*/\1="oar_ro"/' \
          -e 's/^\(SERVER_HOSTNAME\)=.*/\1="server"/' \
          -e 's/^\(LOG_LEVEL\)\=\"2\"/\1\=\"3\"/' \
          -e 's/^#\(JOB_RESOURCE_MANAGER_PROPERTY_DB_FIELD\=\"cpuset\".*\)/\1/' \
          -e 's/^#\(CPUSET_PATH\=\"\/oar\".*\)/\1/' \
          /etc/oar/oar.conf
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="create oar db"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      oar-database --create --db-is-local --db-admin-user root
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="create oar resources"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      oar_resources_add -H $HOSTS_COUNT -C 1 -c 1 -t 1 | tee /tmp/oar_create_resources
      sync
      . /tmp/oar_create_resources
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="start oar-server"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      service oar-server start
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-web-status"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      yum install -y --enablerepo=OAR oar-web-status oar-web-status-pgsql
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="set oar-web-status configs"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      sed -i \
          -e "s/^\(username =\).*/\1 oar_ro/" \
          -e "s/^\(password =\).*/\1 oar_ro/" \
          -e "s/^\(dbtype =\).*/\1 psql/" \
          -e "s/^\(dbport =\).*/\1 5432/" \
          -e "s/^\(hostname =\).*/\1 server/" \
          /etc/oar/monika.conf
      sed -i \
          -e "s/\$CONF\['db_type'\]=\"mysql\"/\$CONF\['db_type'\]=\"pg\"/g" \
          -e "s/\$CONF\['db_server'\]=\"127.0.0.1\"/\$CONF\['db_server'\]=\"server\"/g" \
          -e "s/\$CONF\['db_port'\]=\"3306\"/\$CONF\['db_port'\]=\"5432\"/g" \
          -e "s/\"My OAR resources\"/\"Docker oarcluster resources\"/g" \
          /etc/oar/drawgantt-config.inc.php
      chkconfig httpd on
      service httpd start
      touch /tmp/stamp.${stamp// /_}
    )

  ;;
  frontend)
    stamp="create some users"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      for i in {1..3}; do
        adduser -N user$i
        echo "user$i:vagrant" | chpasswd 
        cp -a /home/vagrant/.ssh /home/user$i/
        cat >> /home/user$i/.bashrc <<'EOF'
function _oarsh_complete_() {
  if [ -n "$OAR_NODEFILE" -a "$COMP_CWORD" -eq 1 ]; then
    local word=${comp_words[comp_cword]}
    local list=$(cat $OAR_NODEFILE | uniq | tr '\n' ' ')
    COMPREPLY=($(compgen -W "$list" -- "${word}"))
  fi
}
complete -o default -F _oarsh_complete_ oarsh

if [ "$PS1" ]; then
   __oar_ps1_remaining_time(){
      if [ -n "$OAR_JOB_WALLTIME_SECONDS" -a -n "$OAR_NODE_FILE" -a -r "$OAR_NODE_FILE" ]; then
         DATE_NOW=$(date +%s)
         DATE_JOB_START=$(stat -c %Y $OAR_NODE_FILE)
         DATE_TMP=$OAR_JOB_WALLTIME_SECONDS
         ((DATE_TMP = (DATE_TMP - DATE_NOW + DATE_JOB_START) / 60))
         echo -n "$DATE_TMP"
      fi
   }
   PS1='[\u@\h|\W]$([ -n "$OAR_NODE_FILE" ] && echo -n "(\[\e[1;32m\]$OAR_JOB_ID\[\e[0m\]-->\[\e[1;34m\]$(__oar_ps1_remaining_time)mn\[\e[0m\])")\$ '
   if [ -n "$OAR_NODE_FILE" ]; then
      echo "[OAR] OAR_JOB_ID=$OAR_JOB_ID"
      echo "[OAR] Your nodes are:"
      sort $OAR_NODE_FILE | uniq -c | awk '{printf("      %s*%d", $2, $1)}END{printf("\n")}' | sed -e 's/,$//'
   fi
fi
EOF
        chown user$i:users /home/user$i -R
      done
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="configure NFS server"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      chkconfig nfs on
      service nfs start
      echo "/home/ ${NETWORK_PREFIX}.0/24(rw,no_root_squash)" > /etc/exports
      exportfs -rv
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install and configure NIS server and client"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      NISDOMAIN="MyNISDomain"
      yum install -y ypserv yp-tools ypbind
      echo "NISDOMAIN=\"$NISDOMAIN\"" >> /etc/sysconfig/network
      domainname $NISDOMAIN
      ypdomainname $NISDOMAIN
      echo "broadcast" >> /etc/yp.conf
      cat <<EOF > /var/yp/securenets
host 127.0.0.1
255.255.255.0 ${NETWORK_PREFIX}.0
EOF
      chkconfig ypserv on
      service rpcbind restart
      service ypserv start
      /usr/lib64/yp/ypinit -m < /dev/null
      chkconfig ypbind on
      chkconfig yppasswdd on
      service ypbind start
      service yppasswdd start
      sed -i \
          -e "s/^\(passwd:     files\)/\1 nis/" \
          -e "s/^\(shadow:     files\)/\1 nis/" \
          -e "s/^\(group:     files\)/\1 nis/" \
          /etc/nsswitch.conf
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-user"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      yum install -y --enablerepo=OAR oar-user oar-user-pgsql
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="set oar config"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      sed -i \
          -e 's/^\(DB_TYPE\)=.*/\1="Pg"/' \
          -e 's/^\(DB_HOSTNAME\)=.*/\1="server"/' \
          -e 's/^\(DB_PORT\)=.*/\1="5432"/' \
          -e 's/^\(DB_BASE_PASSWD\)=.*/\1="oar"/' \
          -e 's/^\(DB_BASE_LOGIN\)=.*/\1="oar"/' \
          -e 's/^\(DB_BASE_PASSWD_RO\)=.*/\1="oar_ro"/' \
          -e 's/^\(DB_BASE_LOGIN_RO\)=.*/\1="oar_ro"/' \
          -e 's/^\(SERVER_HOSTNAME\)=.*/\1="server"/' \
          -e 's/^\(LOG_LEVEL\)\=\"2\"/\1\=\"3\"/' \
          /etc/oar/oar.conf
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install restful api"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      yum install -y --enablerepo=OAR oar-restful-api
      yum install -y oidentd
      sed -i -e "s,#\(LoadModule ident_module modules/mod_ident.so\),\1," /etc/httpd/conf/httpd.conf
      sed -i -e 's/\(OIDENTD_OPTIONS=\).*/\1"-a :: -q -u nobody -g nobody"/' /etc/sysconfig/oidentd
      chkconfig httpd on
      chkconfig oidentd on
      service oidentd start
      service httpd restart
     touch /tmp/stamp.${stamp// /_}
    )

    stamp="setup ssh for oar user"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      rsync -avz server:/var/lib/oar/.ssh /var/lib/oar/
      touch /tmp/stamp.${stamp// /_}
    )

  ;;
  nodes)
    stamp="mount NFS home"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo "${NETWORK_PREFIX}.11:/home /home nfs defaults 0 0" >> /etc/fstab
      mount /home
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install and configure NIS client"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      NISDOMAIN="MyNISDomain"
      yum install -y ypbind
      echo "NISDOMAIN=\"$NISDOMAIN\"" >> /etc/sysconfig/network
      domainname $NISDOMAIN
      ypdomainname $NISDOMAIN
      echo "broadcast" >> /etc/yp.conf
      service rpcbind restart
      chkconfig ypbind on
      service ypbind start
      sed -i \
          -e "s/^\(passwd:     files\)/\1 nis/" \
          -e "s/^\(shadow:     files\)/\1 nis/" \
          -e "s/^\(group:     files\)/\1 nis/" \
          /etc/nsswitch.conf
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-node"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      yum install -y --enablerepo=OAR oar-node
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="start oar-node"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      cat >> /etc/default/oar-node <<'EOF'
OAR_NODE_NAME=$(hostname -f)
OARSERVER="server"
start_oar_node() {
    test -n "$OARSERVER" || exit 0
    ssh $OARSERVER oarnodesetting -s Alive -h $OAR_NODE_NAME
}

stop_oar_node() {
    test -n "$OARSERVER" || exit 0
    ssh $OARSERVER oarnodesetting -s Absent -h $OAR_NODE_NAME
}
EOF
      service oar-node restart
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="setup ssh for oar user"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      rsync -avz server:/var/lib/oar/.ssh /var/lib/oar/
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="forbid user ssh to node"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      cat <<EOF >> /etc/security/access.conf
+ : ALL : LOCAL
- : ALL EXCEPT root oar vagrant : ALL
EOF
      sed -i -e "s/^\(account[[:space:]]\+required[[:space:]]\+pam_\)\(unix.so*\)$/\1\2\n\1access.so/" /etc/pam.d/password-auth
      touch /tmp/stamp.${stamp// /_}
    )

  ;;
  *)
    echo "Error: unknown BOX" 2>&1
    exit 1
  ;;
esac

