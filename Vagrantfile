# -*- mode: ruby -*-
# vi: set ft=ruby :

VAGRANTFILE_API_VERSION = "2"

#
# Provision script
#
$provision_script = <<EOF

echo Hello.

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

  # Run provision script after initializing the box
  config.vm.provision "shell", inline: $provision_script

  # Access Media Cloud's 5000 port by opening localhost:5001
  config.vm.network :forwarded_port, guest: 5000, host: 5001

  # Share Media Cloud's repository as /mediacloud
  # (path is relative to ./script/vagrant)
  config.vm.synced_folder "../../", "/mediacloud"

end
