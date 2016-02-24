#!/bin/bash

set -e

export BOX=$1
export NETWORK_PREFIX=$2
export HOSTS_COUNT=$3
export OAR_FTP_HOST=$4
export OAR_FTP_DISTRIB=$5
export DEBIAN_EXTRA_DISTRIB=$6
export DEBIAN_FRONTEND=noninteractive
export OAR_APT_OPTS=""
export PGSQL_VERSION=9.1

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
#Backports are already in the sources.list file
#  cat <<EOF > /etc/apt/sources.list.d/wheezy-backports.list
#deb http://ftp.debian.org/debian/ wheezy-backports main
#EOF
  cat <<EOF > /etc/apt/apt.conf.d/00defaultrelease
APT::Default-Release "wheezy";
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
Pin: release n=wheezy-backports
Pin-Priority: 998

Package: *
Pin: origin "$OAR_FTP_HOST"
Pin-Priority: 999

Package: *
Pin: release n=wheezy-backports
Pin-Priority: -1

Package: *
Pin: release n=wheezy
Pin-Priority: 500
EOF
  touch /tmp/stamp.${stamp// /_}
)

stamp="update system"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  apt-get update
  apt-get upgrade -y
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
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y nfs-kernel-server
      echo "/home/ ${NETWORK_PREFIX}.0/24(rw,no_subtree_check)" > /etc/exports
      service nfs-kernel-server restart
      exportfs -rv
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install and configure NIS server and client"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      NISDOMAIN="MyNISDomain"
      echo "nis nis/domain string $NISDOMAIN" | debconf-set-selections
      echo '[ "$1" = "nis" ] && exit 101 || exit 0' > /usr/sbin/policy-rc.d;
      chmod +x /usr/sbin/policy-rc.d
      apt-get install -y nis
      rm /usr/sbin/policy-rc.d
      nisdomainname $NISDOMAIN
      sed -i -e "s/^\(NISSERVER=\).*/\1true/" /etc/default/nis
      /usr/lib/yp/ypinit -m < /dev/null 2> /dev/null
      service nis restart
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

    stamp="install oar-web-status"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y $OAR_APT_OPTS oar-web-status libdbd-pg-perl php5-pgsql
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
      #a2enconf oar-web-status # Wheezy uses conf.d, oar-web-status config is linked there upon install.
      service apache2 restart
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install OAR RESTful api"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      apt-get install -y $OAR_APT_OPTS oar-restful-api oidentd libapache2-mod-fastcgi apache2-suexec-custom
      a2enmod ident
      a2enmod rewrite
      a2enmod headers
      a2enmod fastcgi
      a2enmod suexec
      sed -i -e '1s@^/var/www.*@/usr/lib/cgi-bin@' /etc/apache2/suexec/www-data
      sed -i -e 's@#\(FastCgiWrapper /usr/lib/apache2/suexec\)@\1@' /etc/apache2/mods-available/fastcgi.conf
      sed -i -e 's@Deny from all@Allow from all@' /etc/oar/apache2/oar-restful-api.conf
      #a2enconf oar-restfut-api # Wheezy uses conf.d, oar-restful-api config is linked there upon install.
      service apache2 restart
      touch /tmp/stamp.${stamp// /_}
    )

  ;;
  nodes)
    stamp="mount NFS home"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      echo "${NETWORK_PREFIX}.11:/home /home nfs defaults 0 0" >> /etc/fstab
      mount /home
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install and configure NIS client"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      NISDOMAIN="MyNISDomain"
      echo "nis nis/domain string $NISDOMAIN" | debconf-set-selections
      apt-get install -y nis
      echo "+::::::" >> /etc/passwd
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

