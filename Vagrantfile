#-*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
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
    config.vm.provision :shell, inline: "yum install -y mysql-server"
    config.vm.provision :shell, inline: "yum install -y --enablerepo=OAR-testing oar-server oar-server-mysql"
  end
  config.vm.define "frontend" do |m|
    m.vm.box = "chef/centos-6.5"
    m.vm.hostname = "frontend"
    m.vm.network :private_network, ip: "192.168.33.11"
    m.ssh.forward_agent = true
    config.vm.provision :shell, inline: "yum install -y --enablerepo=OAR-testing oar-user oar-user-mysql"
    config.vm.provision :shell, inline: "yum install -y --enablerepo=OAR-testing oar-web-status"
  end
  (1..3).each do |i|
    config.vm.define "node#{i}" do |m|
      m.vm.box = "chef/centos-6.5"
      m.vm.hostname = "node#{i}"
      m.vm.network :private_network, ip: "192.168.33.#{i+100}"
      m.ssh.forward_agent = true
      config.vm.provision :shell, inline: "yum install -y --enablerepo=OAR-testing oar-node"
    end
  end
end
