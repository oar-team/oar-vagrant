#!/bin/bash

set -e

export BOX=$1
export NETWORK_PREFIX=${2}
export NETWORK_MASK=${3}
export NETWORK_SERVER_IP=${4}
export NETWORK_FRONTEND_IP=${5}
export NETWORK_BRIDGE=${6}
export HOSTS_COUNT=${7}
export OAR_FTP_HOST=${8}
export OAR_FTP_DISTRIB=${9}
export DEBIAN_EXTRA_DISTRIB=${10}
export DEBIAN_FRONTEND=noninteractive
export OAR_APT_OPTS=""
export PGSQL_VERSION=11

if [ -z "$BOX" -o -z "$NETWORK_PREFIX" -o -z "$NETWORK_MASK" -o -z "$NETWORK_SERVER_IP" -o -z "$NETWORK_FRONTEND_IP" -o -z "$NETWORK_BRIDGE" -o -z "$HOSTS_COUNT" -o -z "$OAR_FTP_HOST" ]; then
  echo "Error: usage is $0 BOX NETWORK_PREFIX NETWORK_MASK NETWORK_SERVER_IP NETWORK_FRONTEND_IP NETWORK_BRIDGE HOSTS_COUNT OAR_FTP_HOST [OAR_FTP_DISTRIB]" 1>&2
  exit 1
fi

stamp="fix root ssh"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  if [ ! -f /root/.ssh/id_rsa -a ! -f /root/.ssh/id_rsa.pub -a ! -f /root/.ssh/authorized_keys -a ! -f /root/.ssh/config ]; then
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
    cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
    cat <<EOF > /root/.ssh/config
host *
  StrictHostKeyChecking no
EOF
  elif [ ! -f /root/.ssh/id_rsa -o ! -f /root/.ssh/id_rsa.pub -o ! -f /root/.ssh/authorized_keys ]; then
    echo "Error: one of the ssh key files is missing" 1>&2
    exit 1
  fi
  touch /tmp/stamp.${stamp// /_}
)

stamp="fix box bugs"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  rm -rfv /etc/udev/rules.d/70-persistent-net.rules
  touch /tmp/stamp.${stamp// /_}
)

stamp="provision etc hosts"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  echo ${NETWORK_SERVER_IP} server >> /etc/hosts
  echo ${NETWORK_FRONTEND_IP} frontend >> /etc/hosts
  for ((i=1;i<=$HOSTS_COUNT;i++)); do
    echo ${NETWORK_PREFIX}.$((10+i)) node-$i >> /etc/hosts
  done
  touch /tmp/stamp.${stamp// /_}
)

stamp="Drop apt sources repository"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  grep  -v -e "^deb-src" /etc/apt/sources.list > /etc/apt/sources.list.new
  mv /etc/apt/sources.list.new /etc/apt/sources.list
  touch /tmp/stamp.${stamp// /_}
)

stamp="Drop Puppet repository"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  rm -f /etc/apt/sources.list.d/puppetlabs.list
  touch /tmp/stamp.${stamp// /_}
)

stamp="Setup APT sources and preferences packages"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  if [ -n "$OAR_FTP_DISTRIB" ]; then
    cat <<EOF > /etc/apt/sources.list.d/oar-ftp.list
deb http://$OAR_FTP_HOST/oar/2.5/debian/ $OAR_FTP_DISTRIB main
EOF
    wget -q -O- http://$OAR_FTP_HOST/oar/oarmaster.asc | sudo apt-key add -
  fi
  if [ -n "$DEBIAN_EXTRA_DISTRIB" ]; then
    cat <<EOF > /etc/apt/sources.list.d/$DEBIAN_EXTRA_DISTRIB.list
deb http://ftp.debian.org/debian/ $DEBIAN_EXTRA_DISTRIB main
EOF
  fi
#Sid is useless now
#  cat <<EOF > /etc/apt/sources.list.d/sid.list
#deb http://ftp.debian.org/debian/ sid main
#EOF
#Backports are already in the sources.list file
#  cat <<EOF > /etc/apt/sources.list.d/buster-backports.list
#deb http://ftp.debian.org/debian/ buster-backports main
#EOF
  cat <<EOF > /etc/apt/apt.conf.d/00defaultrelease
APT::Default-Release "buster";
EOF
  if [ -n "$DEBIAN_EXTRA_DISTRIB" ]; then
    cat <<EOF > /etc/apt/preferences.d/oar-packages-preferences
Package: oar-* liboar-perl
Pin: release n=$DEBIAN_EXTRA_DISTRIB
Pin-Priority: 999

EOF
  fi
  cat <<EOF >> /etc/apt/preferences.d/oar-packages-preferences
Package: oar-* liboar-perl
Pin: release n=buster-backports
Pin-Priority: 998

Package: *
Pin: origin "$OAR_FTP_HOST"
Pin-Priority: 999

Package: *
Pin: release n=buster-backports
Pin-Priority: -1

Package: *
Pin: release n=sid
Pin-Priority: -1

Package: *
Pin: release n=buster
Pin-Priority: 500
EOF
  touch /tmp/stamp.${stamp// /_}
)

stamp="update system"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  apt-get update
  echo "set grub-pc/install_devices /dev/sda" | debconf-communicate > /dev/null
  apt-get upgrade -y
  touch /tmp/stamp.${stamp// /_}
)

stamp="install common packages"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  apt-get install -y rsync
  touch /tmp/stamp.${stamp// /_}
)

case $BOX in
  server)
    stamp="configure bridge routing"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      sysctl net.ipv4.ip_forward=1
      iptables -t nat -A POSTROUTING -s $NETWORK_PREFIX.0/$NETWORK_MASK -j MASQUERADE
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install and configure postgresql server"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y postgresql-$PGSQL_VERSION
      PGSQL_CONFDIR=/etc/postgresql/$PGSQL_VERSION/main
      sed -i -e "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $PGSQL_CONFDIR/postgresql.conf
      cat <<EOF >> $PGSQL_CONFDIR/pg_hba.conf
#Access to OAR database
host oar all ${NETWORK_PREFIX}.0/24 md5
EOF
      service postgresql restart
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-server package"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y $OAR_APT_OPTS oar-server oar-server-pgsql
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
          -e 's/^\(LOG_LEVEL\)=.*/\1="3"/' \
          -e 's/^#\(JOB_RESOURCE_MANAGER_PROPERTY_DB_FIELD=\"cpuset\".*\)/\1/' \
          -e 's/^#\(CPUSET_PATH\=\"\/oar\".*\)/\1/' \
          -e 's/^#\(WALLTIME_CHANGE_ENABLED\)=.*/\1="yes"/' \
          -e 's/^#\(WALLTIME_MAX_INCREASE\)=.*/\1=-1/' \
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
        # Use /homenfs instead of /home, so that /home/vagrant is left apart on nodes
        mkdir -p /homenfs
        useradd --home /homenfs/user$i -N -m -s /bin/bash user$i
        echo "user$i:vagrant" | chpasswd
        cp -a /root/.ssh /homenfs/user$i/
        cat >> /homenfs/user$i/.bashrc <<'EOF'
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
        chown user$i:users /homenfs/user$i -R
      done
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="configure NFS server"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y nfs-kernel-server
      cat <<EOF > /etc/exports
/homenfs/ ${NETWORK_PREFIX}.0/${NETWORK_MASK} (rw,no_subtree_check)
EOF
      service nfs-kernel-server restart
      exportfs -rv
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install and configure NIS server and client"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      NISDOMAIN="MyNISDomain"
      echo "nis nis/domain string $NISDOMAIN" | debconf-set-selections
      # Workaround to install but not run the nis service (avoid timeout)
      echo '[ "$1" = "nis" ] && exit 101 || exit 0' > /usr/sbin/policy-rc.d;
      chmod +x /usr/sbin/policy-rc.d
      apt-get install -y nis
      rm /usr/sbin/policy-rc.d
      nisdomainname $NISDOMAIN
      sed -i -e "s/^\(NISSERVER=\).*/\1master/" /etc/default/nis
      /usr/lib/yp/ypinit -m < /dev/null 2> /dev/null
      echo "ypserver frontend" >> /etc/yp.conf
      systemctl restart nis
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-user"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y $OAR_APT_OPTS oar-user oar-user-pgsql
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
          -e 's/^\(LOG_LEVEL\)=.*/\1="3"/' \
          -e 's/^#\(WALLTIME_CHANGE_ENABLED\)=.*/\1="yes"/' \
          -e 's/^#\(WALLTIME_MAX_INCREASE\)=.*/\1=-1/' \
          /etc/oar/oar.conf
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="setup ssh for oar user"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      rsync -avz server:/var/lib/oar/.ssh /var/lib/oar/
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-web-status"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y $OAR_APT_OPTS oar-web-status libdbd-pg-perl php-pgsql
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
          -e "s/^\(\$CONF\['db_type'\]=\).*/\1\"pg\";/" \
          -e "s/^\(\$CONF\['db_server'\]=\).*/\1\"server\";/" \
          -e "s/^\(\$CONF\['db_port'\]=\).*/\1\"5432\";/" \
          -e "s/\"My OAR resources\"/\"oar-vagrant resources\";/" \
          /etc/oar/drawgantt-config.inc.php
      a2enmod cgi
      a2enconf oar-web-status
      service apache2 restart
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install OAR RESTful api"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y $OAR_APT_OPTS oar-restful-api oidentd libapache2-mod-fcgid apache2-suexec-custom
      a2enmod ident
      a2enmod rewrite
      a2enmod headers
      a2enmod fcgid
      a2enmod suexec
      sed -i -e '1s@^/var/www.*@/usr/lib/cgi-bin@' /etc/apache2/suexec/www-data
      sed -i -e 's@#\(FastCgiWrapper /usr/lib/apache2/suexec\)@\1@' /etc/apache2/mods-available/fcgid.conf
      sed -i -e 's@Require local@Require all granted@' /etc/oar/apache2/oar-restful-api.conf
      a2enconf oar-restful-api
      service apache2 restart
      touch /tmp/stamp.${stamp// /_}
    )

  ;;
  nodes)
    stamp="configure bridge routing"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      ip route del default
      ip route add default via $NETWORK_SERVER_IP
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="mount NFS home"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y nfs-common
      # Use /homenfs instead of /home, so that /home/vagrant/.ssh/authorized_keys is left untouched
      mkdir -p /homenfs
      echo "${NETWORK_FRONTEND_IP}:/homenfs /homenfs nfs vers=3 0 0" >> /etc/fstab
      mount /homenfs
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install and configure NIS client"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      NISDOMAIN="MyNISDomain"
      echo "nis nis/domain string $NISDOMAIN" | debconf-set-selections
      # Workaround to install but not run the nis service (avoid timeout)
      echo '[ "$1" = "nis" ] && exit 101 || exit 0' > /usr/sbin/policy-rc.d;
      chmod +x /usr/sbin/policy-rc.d
      apt-get install -y nis
      rm /usr/sbin/policy-rc.d
      nisdomainname $NISDOMAIN
      echo "ypserver frontend" >> /etc/yp.conf
      systemctl restart nis
      echo "+::::::" >> /etc/passwd
      sed -i -e 's/^\(\(passwd\|shadow\|group\):.*\)/\1 nis/' /etc/nsswitch.conf

      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-node"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y $OAR_APT_OPTS oar-node
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
- : ALL EXCEPT root oar
EOF
      sed -i -e "s/^#[[:space:]]\+\(account[[:space:]]\+required[[:space:]]\+pam_access.so.*\)$/\1/" /etc/pam.d/login
      touch /tmp/stamp.${stamp// /_}
    )

  ;;
  *)
    echo "Error: unknown BOX" 2>&1
    exit 1
  ;;
esac

