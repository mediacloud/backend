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

Download and install Vagrant 1.3+ from the [Vagrant Downloads page](http://downloads.vagrantup.com/). APT's version is too old at the time of writing.

You'll also need a Provider -- `x86_64` virtualization software package / service of some sort:

* If you would like to set up and run Media Cloud instances locally, [VirtualBox](https://www.virtualbox.org/) is a free, good and supported choice.
* If you would like to set up and run Media Cloud instances remotely, use [Amazon EC2](https://console.aws.amazon.com/ec2/v2/home?region=us-east-1).


Setting up Media Cloud on Vagrant
---------------------------------

Please note that the initial process of setting up Media Cloud may take a long time (~2 hours) as Vagrant will go about upgrading packages, installing a lot of dependencies, compiling and testing Perl, testing Media Cloud itself, etc.


### On VirtualBox

To create a new Media Cloud instance on Vagrant using the VirtualBox provider:

    # (Run once) Add Ubuntu 12.04 as a Vagrant box for later reuse
    vagrant box add precise64 http://files.vagrantup.com/precise64.box

    # Check out a *fresh* copy of Media Cloud from the Git repository
    git clone https://github.com/berkmancenter/mediacloud.git vagrant-mediacloud/
    cd vagrant-mediacloud/

    # Change to the directory in which "Vagrantfile" and other files are located
    cd script/vagrant/

    # Power on the virtual machine
    vagrant up --provider=virtualbox


### On Amazon EC2

To create a new Media Cloud instance on Vagrant using the Amazon EC2 provider:

1. Find out the AWS credentials to be used by Vagrant:
    * `AWS_ACCESS_KEY_ID`:
        * Access Key ID.
        * Available either at the [Your Security Credentials](https://console.aws.amazon.com/iam/home?#security_credential) or the [Security Credentials](https://portal.aws.amazon.com/gp/aws/securityCredentials) pages.
    * `AWS_SECRET_ACCESS_KEY`:
        * Secret Access Key.
        * Available either at the [Your Security Credentials](https://console.aws.amazon.com/iam/home?#security_credential) or the [Security Credentials](https://portal.aws.amazon.com/gp/aws/securityCredentials) pages.
    * `AWS_KEYPAIR_NAME` and `AWS_SSH_PRIVKEY`:
        1. Go to the [EC2 - Key Pairs](https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#KeyPairs:) page.
        2. Click "Create Key Pair", name it `development`.
        3. Download `development.pem`, save it as `~/path/to/development.pem`.
        4. `AWS_KEYPAIR_NAME="development"`
        5. `AWS_SSH_PRIVKEY="~/path/to/development.pem"`
    * `AWS_SECURITY_GROUP`:
        1. Go to the [EC2 - Security Groups](https://console.aws.amazon.com/ec2/home?region=us-east-1#s=SecurityGroups) page.
        2. Click "Create Security Group", name it `default`.
        3. Allow "Inbound SSH traffic" from `0.0.0.0/0`.
        4. Allow "Inbound ICMP traffic" of type "All" from `0.0.0.0/0`.
        5. Allow "Inbound TCP traffic" through Port Range "5000" from `0.0.0.0/0`.
        6. Allow "Inbound TCP traffic" through Port Range "3000" from `0.0.0.0/0`.
        7. Click "Apply Rule Changes".
        8. `AWS_SECURITY_GROUP="default"`
2. Run:

        # (Run once) Install the "vagrant-aws" plugin
        vagrant plugin install vagrant-aws

        # Check out a *fresh* copy of Media Cloud from the Git repository
        git clone https://github.com/berkmancenter/mediacloud.git vagrant-mediacloud/
        cd vagrant-mediacloud/

        # Change to the directory in which "Vagrantfile" and other files are located
        cd script/vagrant/

        # (Run once) Add the "dummy" AWS box for later reuse
        vagrant box add ubuntu_aws aws_ec2_dummy.box

        # Set up the required environment variables with AWS credentials to be used
        # by Vagrant
        export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
        export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG"
        export AWS_KEYPAIR_NAME="development"
        export AWS_SSH_PRIVKEY="~/development.pem"
        export AWS_SECURITY_GROUP="default"

        # Power on the virtual machine
        vagrant up --provider=aws


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

#### On VirtualBox

Port forwarding is set up as such:

* Port `5000` on the guest machine is automatically forwarded to port `5001` on the host machine.
* Port `3000` on the guest machine is automatically forwarded to port `3001` on the host machine.

To start the Media Cloud web service, run:

    host$ vagrant ssh
    vagrant$ cd /mediacloud
    vagrant$ ./script/start_mediacloud_server.sh

and then open `http://127.0.0.1:5001/` on your *host* machine to access Media Cloud web interface on the guest machine.

#### On Amazon EC2

EC2 instances don't support port forwarding like VirtualBox does, so you'll have to access the Media Cloud web service directly.

To start the Media Cloud web service:

1. Connect to a running EC2 instance:
    * via Vagrant:
        * `host$ vagrant ssh`, or
    * via EC2 Management Console:
        1. Open [EC2 Management Console](https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#Instances:)
        2. Select a running Media Cloud instance.
        3. Click "Connect".
        4. Copy the SSH command provided in the "Example" section and run it.
2. Start the Media Cloud web service:

        vagrant$ cd /mediacloud
        vagrant$ ./script/start_mediacloud_server.sh

3. Access the Media Cloud web service using its Public DNS.
    * For example, if the Public DNS of the EC2 instance is `ec2-54-224-57-211.compute-1.amazonaws.com`, access the web service by opening `http://ec2-54-224-57-211.compute-1.amazonaws.com:5000/`.


Testing Media Cloud with Vagrant
--------------------------------

Directory `script/vagrant/` contains a script `run_install_test_suite_on_vagrant.sh` that:

1. Clones a fresh copy of Media Cloud from Git,
2. Starts a new temporary instance of Vagrant with the Media Cloud repository attached as a shared folder,
3. If the Media Cloud installation succeeded, cleans up and returns with a zero exit status code, or
4. If the Media Cloud installation failed, leaves everything inact, shuts down the Vagrant instance and returns with a non-zero exit code.

You can use the script to automatically and periodically test Media Cloud installation process and run the full test suite.


### On VirtualBox

To test Media Cloud on a VirtualBox instance, copy the `run_install_test_suite_on_vagrant.sh` script somewhere and run:

    ./run_install_test_suite_on_vagrant.sh virtualbox


### On Amazon EC2

To test Media Cloud on a Amazon EC2 instance, copy the `run_install_test_suite_on_vagrant.sh` script somewhere and run:

    AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" \
    AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG" \
    AWS_KEYPAIR_NAME="development" \
    AWS_SSH_PRIVKEY="~/development.pem" \
    AWS_SECURITY_GROUP="default" \
    ./run_install_test_suite_on_vagrant.sh aws
