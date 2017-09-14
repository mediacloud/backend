# Ansible setup

Media Cloud uses [Ansible](https://www.ansible.com/) for:

* Initial host setup for running Media Cloud;
* Automatic code deployments;
* Maintenance of Docker image used on Travis tests.


## Configuration

To use Ansible, you might want to set up an inventory file located at `ansible/inventory/hosts` with the hosts you would like to run Media Cloud on.

The `ansible/inventory/` directory has a sample inventory file `hosts.sample` with some notes on optional variables that one can set.


## Set up

To set up localhost with Media Cloud, run:

```shell
cd ansible/	# to read ansible.cfg
ansible-playbook --limit localhost setup.yml
```

To set up a remote host with Media Cloud, run:

```shell
cd ansible/	# to read ansible.cfg
ansible-playbook --limit your-host setup.yml
```


## Deploy

To deploy Media Cloud code updates on a remote host (together with Apache / Supervisor restarts, code pull, etc.), run:

```shell
cd ansible/	# to read ansible.cfg
ansible-playbook --limit your-host deploy.yml
```
