Hosting
=======

This directory holds files with details about hosting media cloud at our core installation at MIT.  These are the docs
that our local team uses to maintain our infrastructure.  The details of the servers involved are specific to
our setup, but there is lots of generally useful information about how to administer the various components
of a media cloud installation.

The core machines of the media cloud hosting infrastructure are:

* mcdb1 - runs core mc installation and PostgreSQL database
* mcdb2 - will run replicant PostgreSQL database and one off processing jobs like topics (in development)
* mcquery[1234] - run Solr cluster that backs mc searches
* mcnlp - runs a web service version of Stanford CoreNLP, through which we generate CoreNLP annotations

These machines are all within the media.mit.edu domain and all currently run ubuntu (12.04 or 16.04).  They are all 16 core,
192G RAM machines with a RAID-1 360G spinning disk array as the system disk.
