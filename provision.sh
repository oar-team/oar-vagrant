#!/bin/bash

set -e

export BOX=$1
export HOSTS_COUNT=$2
if [ -z "$BOX" -o -z "$HOSTS_COUNT" ]; then
  echo "Error: syntax error, usage is $0 BOX HOSTS_COUNT" 1>&2
  exit 1
fi

stamp="provision etc hosts"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  echo 192.168.33.10 server >> /etc/hosts 
  echo 192.168.33.11 frontend >> /etc/hosts 
  for ((i=1;i<=$HOSTS_COUNT;i++)); do
    echo 192.168.33.$((100+i)) node-$i >> /etc/hosts 
  done
  touch /tmp/stamp.${stamp// /_}
)

stamp="provision EPEL repo"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  rpm -Uvh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
  touch /tmp/stamp.${stamp// /_}
)

stamp="provision OAR-Testing repo"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  cat <<'EOF' | tee /etc/yum.repos.d/OAR-testing.repo
[OAR-testing]
name=OAR-testing
baseurl=http://oar-ftp.imag.fr/oar/2.5/rpm/centos6/testing/
gpgcheck=1
gpgkey=http://oar-ftp.imag.fr/oar/oarmaster.asc
enabled=0
EOF
  touch /tmp/stamp.${stamp// /_}
)

stamp="install man package"
[ -e /tmp/stamp.${stamp// /_} ] || (
  echo -ne "##\n## $stamp\n##\n" ; set -x
  yum install -y man
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
host oar all 192.168.33.0/24 md5 
EOF
      chkconfig postgresql on
      service postgresql restart
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-server package"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      yum install -y --enablerepo=OAR-testing oar-server oar-server-pgsql
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
  ;;
  frontend)
    stamp="create some users"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      for i in {1..3}; do
        adduser -N user$i
      done
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="configure NFS server"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      chkconfig nfs on
      service nfs start
      echo "/home/ 192.168.33.0/24(rw,no_root_squash)" > /etc/exports
      exportfs -rv
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install NIS server packages"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      yum install -y ypserv yp-tools ypbind
      touch /tmp/stamp.${stamp// /_}
    )


    stamp="configure NIS server"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      NISDOMAIN="MyNISDomain"
      echo "domain $NISDOMAIN server 192.168.33.11" >> /etc/yp.conf
      echo "NISDOMAIN=\"$NISDOMAIN\"" >> /etc/sysconfig/network
      domainname $NISDOMAIN
      ypdomainname $NISDOMAIN
      cat <<EOF > /var/yp/securenets
host 127.0.0.1
255.255.255.0 192.168.33.0
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
      yum install -y --enablerepo=OAR-testing oar-user oar-user-pgsql
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install oar-web-status"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      yum install -y --enablerepo=OAR-testing oar-web-status oar-web-status-pgsql
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
      rsync -avz server:/var/lib/oar/.ssh /var/lib/oar/ --exclude "id_rsa"
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install httpd"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      yum install httpd
      chkconfig httpd on
      service httpd start
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="set monika config"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      sed -i \
          -e "s/^\(username.*\)oar.*/\1oar_ro/" \
          -e "s/^\(password.*\)oar.*/\1oar_ro/" \
          -e "s/^\(dbtype.*\)mysql.*/\1psql/" \
          -e "s/^\(dbport.*\)3306.*/\15432/" \
          -e "s/^\(hostname.*\)localhost.*/\1server/" \
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
      echo "192.168.33.11:/home /home nfs defaults 0 0" >> /etc/fstab
      mount /home
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="install NIS"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      yum install -y ypbind
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="configure NIS client"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      NISDOMAIN="MyNISDomain"
      echo "domain $NISDOMAIN server 192.168.33.11" >> /etc/yp.conf
      echo "NISDOMAIN=\"$NISDOMAIN\"" >> /etc/sysconfig/network
      domainname $NISDOMAIN
      ypdomainname $NISDOMAIN
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
      yum install -y --enablerepo=OAR-testing oar-node
      touch /tmp/stamp.${stamp// /_}
    )

    stamp="setup ssh for oar user"
    [ -e /tmp/stamp.${stamp// /_} ] || (
      echo -ne "##\n## $stamp\n##\n" ; set -x
      rsync -avz server:/var/lib/oar/.ssh /var/lib/oar/ --exclude "id_rsa"
      touch /tmp/stamp.${stamp// /_}
    )

  ;;
  *)
    echo "Error: unknown BOX" 2>&1
    exit 1
  ;;
esac

