Monitoring
==========

We use three modes of monitoring the system to make sure everything is humming nicely: cron jobs, munin, and nagios.

Cron Jobs
---------

We have a number of cron jobs that email us either regular reports or reports of something looks fishy.  Our production
cron jobs are documented [here](cron-jobs.markdown).

Munin
-----

We have a munin installation that monitors various indicators of our story processing system (number of stories crawled,
number of stories in the extractor queue, etc) as well as some basic system information on the core system.  Munin
includes a web interface that provides historical data about the various metrics. We keep the mediacloud munin
installation in a [separate github repo](https://github.com/berkmancenter/mediacloud-munin).

Nagios
------

In addition to the munin monitoring, we monitor each of our mit servers using nagios.  Nagios monitors basic system
health (disk space, free memory, load, etc) as well as some specific media cloud metrics (presence of java processes
on solr servers, etc).  Nagios warning thresholds are monitored in the /etc/local/nagios/etc directory of each
monitored server.  Media labs necsys runs the nagios server, which includes a web interface to disable monitoring
of specific hosts / servers as needed.

The most common nagios report is a notice that we need to update packages on the ubuntu installation, which looks like
this:

```
APT WARNING: 1 packages available for upgrade (0 critical updates).
```

To update all packages on all mit servers, I run:

```
for i in mcquery1 mcquery2 mcquery3 mcquery4 mcdb1 mcnlp civicprod civicdev; do ssh -t $i sudo apt-get upgrade; done
```

This requires many password entries and confirmations of packages, but I prefer the occasional hassle to the security
and reliability costs of automating the updates more.
