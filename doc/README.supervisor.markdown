Media Cloud's Supervisor daemons
================================

Media Cloud comes with a [Supervisor](http://supervisord.org/) configuration file which makes it easier to start, stop, restart, monitor and log various background (daemon) processes that are needed for Media Cloud to work.


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

* `supervisord.user.mongoDB.conf` - MongoDB service
* `supervisord.user.show_ulimit_s.conf` - some other service


Links
-----

* [Supervisor](http://supervisord.org/)
* [Supervisor configuration file syntax](http://supervisord.org/configuration.html)
* [Supervisor on OS X](http://nicksergeant.com/running-supervisor-on-os-x/)
