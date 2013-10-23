Media Cloud on Vagrant
======================

You might want to run Media Cloud with [Vagrant](http://www.vagrantup.com/) in the following cases:

* You don't run a supported operating system (Ubuntu or Mac OS X).
* You want to try out Media Cloud without making any changes on the host system.
* You don't have permissions to install system-wide packages on the host system for running Media Cloud.
* You want to automatically test the installation process of Media Cloud.

Media Cloud provides a lean `Vagrantfile` script located in `script/vagrant/` that you can use to set up a Media Cloud instance on Vagrant.


Installing Vagrant and its dependencies
---------------------------------------

Download and install Vagrant 1.3+ from the [Vagrant Downloads page](http://downloads.vagrantup.com/) `*`.

You'll also need a Provider -- `x86_64` virtualization software package of some sort. [VirtualBox](https://www.virtualbox.org/) is a free, good and supported choice.

`*` APT's version is too old at the time of writing


Setting up Media Cloud on Vagrant
---------------------------------

To create a new Media Cloud instance on Vagrant:

    # (Run once) Add Ubuntu 12.04 as a Vagrant box for later reuse
    vagrant box add precise64 http://files.vagrantup.com/precise64.box

    # Check out a *fresh* copy of Media Cloud from the Git repository
    git clone https://github.com/berkmancenter/mediacloud.git vagrant-mediacloud/
    cd vagrant-mediacloud/
    git checkout vagrant

    # Change to the directory in which "Vagrantfile" is located
    cd script/vagrant/

    # Power on the virtual machine
    vagrant up

The initial process of setting up Media Cloud may take a long time (~2 hours) as Vagrant will go about upgrading packages, installing a lot of dependencies, compiling and testing Perl, testing Media Cloud itself, etc.


Running Media Cloud on Vagrant
------------------------------

The Git repository that you have cloned previously is automatically mounted to `/mediacloud` directory on the virtual machine.


### Powering on the virtual machine

To power on the guest machine, run:

    vagrant up


### Destroying the virtual machine

To destroy the virtual machine (before recreating), run:

    vagrant destroy


### SSHing to the virtual machine

To SSH to the guest machine, run:

    vagrant ssh


### Running Media Cloud's web service

Port `5000` on the guest machine is automatically forwarded to port `5001` on the host machine.

So, to start the Media Cloud web service, run:

    host$ vagrant ssh
    vagrant$ cd /mediacloud
    vagrant$ ./script/start_mediacloud_server.sh

and then open `http://127.0.0.1:5001/` on your *host* machine to access Media Cloud web interface on the guest machine.


### Testing Media Cloud with Vagrant

Directory `script/vagrant/` contains a script `run_install_test_suite_on_vagrant.sh` that:

1. Clones a fresh copy of Media Cloud from Git,
2. Starts a new temporary instance of Vagrant with the Media Cloud repository attached as a shared folder,
3. If the Media Cloud installation succeeded, cleans up and returns with a zero exit status code, or
4. If the Media Cloud installation failed, leaves everything inact, shuts down the Vagrant instance and returns with a non-zero exit code.

You can use the script to automatically and periodically test Media Cloud installation process and run the full test suite.
