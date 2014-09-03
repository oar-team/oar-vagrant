#!/bin/bash

set -e

export BOX=$1
export HOSTS_COUNT=$2
export DEBIAN_FRONTEND=noninteractive
export PGSQL_VERSION=9.1
if [ -z "$BOX" -o -z "$HOSTS_COUNT" ]; then
  echo "Error: syntax error, usage is $0 BOX HOSTS_COUNT" 1>&2
  exit 1
fi

stamp="provision etc hosts"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  echo 192.168.34.10 server >> /etc/hosts
  echo 192.168.34.11 frontend >> /etc/hosts
  for ((i=1;i<=$HOSTS_COUNT;i++)); do
    echo 192.168.34.$((100+i)) node-$i >> /etc/hosts
  done
  touch /tmp/stamp.${stamp// /_}
)

stamp="provision OAR-Testing repo"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  # Add the OAR testing repository
  echo "deb http://oar-ftp.imag.fr/oar/2.5/debian/ sid-unstable main" > /etc/apt/sources.list.d/oar.list
  curl http://oar-ftp.imag.fr/oar/oarmaster.asc | sudo apt-key add -
  touch /tmp/stamp.${stamp// /_}
)

case $BOX in
  server)
    stamp="install and configure postgresql server"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y postgresql-$PGSQL_VERSION
      PGSQL_CONFDIR=/etc/postgresql/$PGSQL_VERSION/main
      sed -i -e "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $PGSQL_CONFDIR/postgresql.conf
      cat <<EOF >> $PGSQL_CONFDIR/pg_hba.conf
#Access to OAR database
host oar all 192.168.34.0/24 md5
EOF
      service postgresql restart
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-server package"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y oar-server oar-server-pgsql
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

  ;;
  frontend)
    stamp="create some users"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      for i in {1..3}; do
        useradd -N -m -s /bin/bash user$i
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
      apt-get install -y nfs-kernel-server
      echo "/home/ 192.168.34.0/24(rw,no_root_squash)" > /etc/exports
      exportfs -rv
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install NIS server packages"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      touch /tmp/stamp.${stamp// /_}
    )


    stamp="install and configure NIS server"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      NISDOMAIN="MyNISDomain"
      echo "nis nis/domain string $NISDOMAIN" | debconf-set-selections
      apt-get install -y nis
      sed -i -e "s/^\(NISSERVER=\).*/\1true/" /etc/default/nis
      echo "domain $NISDOMAIN server 192.168.34.11" >> /etc/yp.conf
      cat <<EOF > /var/yp/securenets
host 127.0.0.1
255.255.255.0 192.168.34.0
EOF
      /usr/lib/yp/ypinit -m < /dev/null
      echo "+::::::" > /etc/passwd
      echo "+:::" > /etc/group
      service nis restart
#      sed -i \
#          -e "s/^\(passwd:     files\)/\1 nis/" \
#          -e "s/^\(shadow:     files\)/\1 nis/" \
#          -e "s/^\(group:     files\)/\1 nis/" \
#          /etc/nsswitch.conf
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-user"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y oar-user oar-user-pgsql
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-web-status"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y oar-web-status oar-web-status-pgsql
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

    stamp="setup ssh for oar user"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      rsync -avz server:/var/lib/oar/.ssh /var/lib/oar/
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install httpd"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="set monika config"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      sed -i \
          -e "s/^\(username =\).*/\1 oar_ro/" \
          -e "s/^\(password =\).*/\1 oar_ro/" \
          -e "s/^\(dbtype =\).*/\1 psql/" \
          -e "s/^\(dbport =\).*/\1 5432/" \
          -e "s/^\(hostname =\).*/\1 server/" \
          /etc/oar/monika.conf
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="set drawgantt-svg config"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      sed -i \
          -e "s/\$CONF\['db_type'\]=\"mysql\"/\$CONF\['db_type'\]=\"pg\"/g" \
          -e "s/\$CONF\['db_server'\]=\"127.0.0.1\"/\$CONF\['db_server'\]=\"server\"/g" \
          -e "s/\$CONF\['db_port'\]=\"3306\"/\$CONF\['db_port'\]=\"5432\"/g" \
          -e "s/\"My OAR resources\"/\"Docker oarcluster resources\"/g" \
          /etc/oar/drawgantt-config.inc.php
      touch /tmp/stamp.${stamp// /_}
    )

  ;;
  nodes)
    stamp="mount NFS home"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo "192.168.34.11:/home /home nfs defaults 0 0" >> /etc/fstab
      mount /home
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install and configure NIS"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      NISDOMAIN="MyNISDomain"
      echo "nis nis/domain string $NISDOMAIN" | debconf-set-selections
      apt-get install -y nis
      echo "domain $NISDOMAIN server 192.168.34.11" >> /etc/yp.conf
      echo "+::::::" > /etc/passwd
      echo "+:::" > /etc/group
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-node"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y oar-node
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="setup ssh for oar user"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      rsync -avz server:/var/lib/oar/.ssh /var/lib/oar/
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="start oar-node"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      service oar-node start
      touch /tmp/stamp.${stamp// /_}
    )

  ;;
  *)
    echo "Error: unknown BOX" 2>&1
    exit 1
  ;;
esac

