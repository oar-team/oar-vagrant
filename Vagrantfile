#-*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"
HOSTS_COUNT = 1

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.provision :shell, inline: "echo 192.168.33.10 server >> /etc/hosts" 
  config.vm.provision :shell, inline: "echo 192.168.33.11 frontend >> /etc/hosts" 
  (1..HOSTS_COUNT).each do |i|
    config.vm.provision :shell, inline: "echo 192.168.33.#{100+i} node-#{i} >> /etc/hosts" 
  end
  config.vm.provision :shell, inline: "rpm -Uvh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm"
  config.vm.provision :shell, inline: "cat <<'EOF' | tee /etc/yum.repos.d/OAR-testing.repo
[OAR-testing]
name=OAR-testing
baseurl=http://oar-ftp.imag.fr/oar/2.5/rpm/centos6/testing/
gpgcheck=1
gpgkey=http://oar-ftp.imag.fr/oar/oarmaster.asc
enabled=0
EOF"
  config.vm.define "server", primary: true do |m|
    m.vm.box = "chef/centos-6.5"
    m.vm.hostname = "server"
    m.vm.network :private_network, ip: "192.168.33.10"
    m.ssh.forward_agent = true
    m.vm.provision :shell, inline: "yum install -y postgresql-server"
    m.vm.provision :shell, inline: "service postgresql initdb"
    m.vm.provision :shell, inline: <<'END'
PGSQL_CONFDIR=/var/lib/pgsql/data
sed -i -e "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $PGSQL_CONFDIR/postgresql.conf
sed -i -e "s/\(host \+all \+all \+127.0.0.1\/32 \+\)ident/\1md5/" \
       -e "s/\(host \+all \+all \+::1\/128 \+\)ident/\1md5/" $PGSQL_CONFDIR/pg_hba.conf
END
    m.vm.provision :shell, inline: "service postgresql restart"
    m.vm.provision :shell, inline: "yum install -y --enablerepo=OAR-testing oar-server oar-server-pgsql"
    m.vm.provision :shell, inline: <<'END'
sed -i -e 's/^\(LOG_LEVEL\)\=\"2\"/\1\=\"3\"/' \
       -e 's/^#\(JOB_RESOURCE_MANAGER_PROPERTY_DB_FIELD\=\"cpuset\".*\)/\1/' \
       -e 's/^#\(CPUSET_PATH\=\"\/oar\".*\)/\1/' \
       -e 's/^\(DB_BASE_PASSWD\)=.*/\1="oar"/' \
       -e 's/^\(DB_BASE_LOGIN\)=.*/\1="oar"/' \
       -e 's/^\(DB_BASE_PASSWD_RO\)=.*/\1="oar_ro"/' \
       -e 's/^\(DB_BASE_LOGIN_RO\)=.*/\1="oar_ro"/' /etc/oar/oar.conf
END
    m.vm.provision :shell, inline: "oar-database --create --db-is-local --db-admin-user root"
    m.vm.provision :shell, inline: "oar_resources_add -H #{HOSTS_COUNT} -C 1 -c 1 -t 1 -o /tmp/oar_create_resources"
    m.vm.provision :shell, inline: ". /tmp/oar_create_resources"
  end
  config.vm.define "frontend" do |m|
    m.vm.box = "chef/centos-6.5"
    m.vm.hostname = "frontend"
    m.vm.network :private_network, ip: "192.168.33.11"
    m.ssh.forward_agent = true
    (1..3).each do |u|
      m.vm.synced_folder "user#{u}", "/home/user#{u}", create: true
      m.vm.provision :shell, inline: <<END
umount /home/user#{u} && \
adduser -M user#{u}
mount -t vboxsf -o uid=$(id -u user#{u}),gid=$(id -g user#{u}) /home/user#{u} /home/user#{u}
END
    end
    m.vm.provision :shell, inline: "yum install -y --enablerepo=OAR-testing oar-user oar-user-pgsql"
    m.vm.provision :shell, inline: "yum install -y --enablerepo=OAR-testing oar-web-status oar-web-status-pgsql"
  end
  (1..HOSTS_COUNT).each do |i|
    config.vm.define "node-#{i}" do |m|
      m.vm.box = "chef/centos-6.5"
      m.vm.hostname = "node-#{i}"
      m.vm.network :private_network, ip: "192.168.33.#{i+100}"
      m.ssh.forward_agent = true
      (1..3).each do |u|
        m.vm.synced_folder "user#{u}", "/home/user#{u}", create: true
        m.vm.provision :shell, inline: <<END
umount /home/user#{u} && \
adduser -M user#{u}
mount -t vboxsf -o uid=$(id -u user#{u}),gid=$(id -g user#{u}) /home/user#{u} /home/user#{u}
END
    end
      m.vm.provision :shell, inline: "yum install -y --enablerepo=OAR-testing oar-node"
    end
  end
end
