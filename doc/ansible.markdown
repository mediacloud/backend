# Ansible setup

Media Cloud uses [Ansible](https://www.ansible.com/) for:

* Initial host setup for running Media Cloud;
* Automatic code deployments;
* Maintenance of Docker image used on Travis tests.


## Configuration

To use Ansible, you might want to set up an inventory file located at `ansible/inventory/hosts.yml` with the hosts you would like to run Media Cloud on.

The `ansible/inventory/` directory has a sample inventory file `hosts.sample.yml` with some notes on optional variables that one can set. Additionally please see [`hosts.yml` syntax example](https://github.com/ansible/ansible/blob/devel/examples/hosts.yaml).


## Set up

To **set up localhost**, run:

```shell
cd ansible/	# to read ansible.cfg
ansible-playbook --limit localhost setup.yml
```

To **set up a remote host**, run:

```shell
cd ansible/	# to read ansible.cfg
ansible-playbook --limit your-host setup.yml
```


## Deploy

To **deploy code updates on a remote host** (together with Apache / Supervisor restarts, code pull, etc.), run:

```shell
cd ansible/	# to read ansible.cfg
ansible-playbook --limit your-host deploy.yml
```


## Tips

All tasks in every Ansible role are tagged with the role's name, e.g. every task in `pam-limits` role is tagged with `pam-limits` tag.

So, to **run only a single role**, you can use `--tags` parameter:

```shell
cd ansible/	# to read ansible.cfg
ansible-playbook --limit your-host --tags pam-limits setup.yml
```

To **skip some roles from running**, you can use `--skip-tags` parameter:

```shell
cd ansible/	# to read ansible.cfg
ansible-playbook --limit your-host --skip-tags pam-limits setup.yml
```
