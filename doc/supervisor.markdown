Media Cloud's Supervisor daemons
================================

Media Cloud comes with a [Supervisor](http://supervisord.org/) configuration file which makes it
easier to start, stop, restart, monitor and log various background (daemon) processes that are needed for Media Cloud
to work.
 
Configuring `supervisord`
-------------------------

Our supervisord configuration is templated to allow us to configure most supervisor settings for individual daemons
in mediawords.yml.  To change the number of procs and autostart settings of each supervisor daemon, edit the
supervisor section in mediawords.yml.

The full configuration is kept in supervisord/supervisord.conf.tt2 (which is used to regenerate
supervisord/supervisord.conf every time supervisord/supervisord.sh is run).  To add a new service or edit other
more advanced options of supervisord, edit the supervisord.conf.tt2.

Starting `supervisord`
----------------------

To start the Supervisor daemon `supervisord`:

    supervisor/supervisord.sh


Starting `supervisorctl`
------------------------

To start the Supervisor control tool `supervisorctl`:

    supervisor/supervisorctl.sh

Using the tool, you can `start`, `stop`, `restart` various services, `reload` configuration and do various other things.


Accessing logs
--------------

Supervisor process logs are kept in `./data/supervisor_logs/` by default.


Adding a custom service to Supervisor configuration
---------------------------------------------------

To add a custom service (daemon) to the Supervisor configuration, create a configuration file `supervisord.user.SERVICE_NAME.conf` in `./supervisor/` and then reload the configuration.

The newly created configuration file will be automatically included by the main configuration file `supervisord.conf`.

Examples:

* `supervisord.user.munin.conf` - Munin service
* `supervisord.user.show_ulimit_s.conf` - some other service


Links
-----

* [Supervisor](http://supervisord.org/)
* [Supervisor configuration file syntax](http://supervisord.org/configuration.html)
* [Supervisor on OS X](http://nicksergeant.com/running-supervisor-on-os-x/)
