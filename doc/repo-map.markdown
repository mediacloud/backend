# MC Repository Road Map

Here's a brief road map of the MC repository

* `mediawords.yml` - mediacloud configuration

* `cpanfile` - list of perl modules required by the system

* `doc/` - system docs

* `root/` - web app template files

* `solr/` - solr installation

* `supervisor/*` - supervisord installation that runs the various daemons to crawl feeds, extract text, annotate
  stories, etc.

* `script/` - command line scripts that run the various aspects of the system.

* `script/mediawords.sql` - sql definition of postgres database

* `script/run_with_carton.sh` - shell script that should be used to run all perl scripts

* `script/mediawords_server.pl` - run the stand alone version of the catalyst
  web application (which as with any catalyst app can also run via cgi, fcgi,
  or mod_perl)

* `script/mediawords_crawl.pl` - crawl the web for the feeds entered into the
  web application

* `lib/*` - perl modules that implement the bulk of the functionality of the
  system

* `lib/MediaWords/Controller/*` - catalyst controller classes that implement
  the various pages of the web app

* `lib/MediaWords/Crawler/*` - crawler implementation

* `lib/MediaWords/Crawler/Extractor.pm` - text extraction implementation

* `lib/DBIx/Simple/MediaWords.pm` - local sub class of DBIx::Simple that
  Media Cloud uses for database access

* `data/` - directory for all data files, meaning anything that gets written by the system (cache files, etc).

* `t/` - perl unit tests (some are also within lib/)
