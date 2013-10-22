# -*- mode: ruby -*-
# vi: set ft=ruby :

VAGRANTFILE_API_VERSION = "2"


#
# Provision script for privileged user (root)
#
$provision_script_root = <<EOF

echo Hello.

EOF


#
# Provision script for unprivileged user (vagrant)
#
$provision_script_user = <<EOF

echo I am unprivileged.

EOF


#
# Vagrant configuration
#
Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|

  # Ubuntu 12.04 (64 bit)
  config.vm.box = "precise64"
  config.vm.box_url = "http://files.vagrantup.com/precise64.box"

  # Hostname
  config.vm.hostname = "mediacloud.local"

  # Provision scripts
  config.vm.provision "shell", privileged: true, inline: $provision_script_root
  config.vm.provision "shell", privileged: false, inline: $provision_script_user

  # Access Media Cloud's 5000 port by opening localhost:5001
  config.vm.network :forwarded_port, guest: 5000, host: 5001

  # Share Media Cloud's repository as /mediacloud
  # (path is relative to ./script/vagrant)
  config.vm.synced_folder "../../", "/mediacloud"

end
