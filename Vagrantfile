#-*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"
HOSTS_COUNT = 1

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "oar-team/centos-6.5"
  config.vm.synced_folder ".", "/vagrant", create: true
  config.vm.define "server", primary: true do |m|
    m.vm.hostname = "server"
    m.vm.network :private_network, ip: "192.168.33.10"
    m.ssh.forward_agent = true
    m.vm.provision :shell, path: "provision.sh", args: "server #{HOSTS_COUNT}", privileged: true
  end
  config.vm.define "frontend" do |m|
    m.vm.hostname = "frontend"
    m.vm.network :private_network, ip: "192.168.33.11"
    m.ssh.forward_agent = true
    (1..3).each do |u|
      m.vm.synced_folder "user#{u}", "/home/user#{u}", create: true
    end
    m.vm.provision :shell, path: "provision.sh", args: "frontend #{HOSTS_COUNT}", privileged: true
  end
  (1..HOSTS_COUNT).each do |i|
    config.vm.define "node-#{i}" do |m|
      m.vm.hostname = "node-#{i}"
      m.vm.network :private_network, ip: "192.168.33.#{i+100}"
      m.ssh.forward_agent = true
      (1..3).each do |u|
        m.vm.synced_folder "user#{u}", "/home/user#{u}", create: true
      end
      m.vm.provision :shell, path: "provision.sh", args: "nodes #{HOSTS_COUNT}", privileged: true
    end
  end
end