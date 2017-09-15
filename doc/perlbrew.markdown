# Adding new dependency modules

To add a new Perl dependency module:

* Add the new module under variables in Ansible's `perl-dependencies` role (please see `ansible/roles/perl-dependencies/vars/main.yml`).
* Rerun Ansible script.


# Running Scripts

95% of the time you'll just use the `run_in_env.sh` wrapper to run scripts:

    ./script/run_in_env.sh perl ./script/SCRIPT_NAME.pl ARG1 ARG2

Note it's best to run this script from the base directory of the Media Cloud
install. However, this only matters if the arguments after the script are file
paths.
