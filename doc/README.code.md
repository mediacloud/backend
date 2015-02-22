# Code

This code consists primarily of a Catalyst web app that manages the media
sources and feeds that Media Cloud processes and of a collection of stand
alone scripts that download, extract, index, and tag the content of those
media sources and feeds.

Here's a brief road map of the code included in this release:

* `script/*` - command line scripts that run the various aspects of the system.

* `script/mediawords.sql` - sql definition of postgres database

* `script/mediawords_server.pl` - run the stand alone version of the catalyst
  web application (which as with any catalyst app can also run via cgi, fcgi,
  or mod_perl)

* `script/mediawords_crawl.pl` - crawl the web for the feeds entered into the
  web application.

* `script/mediawords_extract_and_vector_locally.pl` - extract the substantive
  text from and add tags to all newly downloaded content.
  
* `script/mediawords_update_story_vectors.pl` - index all extracted text in
  the postgres full text search system and create the word index that 
  supports the topic explorer word frequency analysis.
  
* `script/mediawords_generate_topic_reports.pl` - generate the word cloud / 
  topic reports.  
  
* `script/mediawords_create_*` - create the denormalized tables for the
  mediacloud.org top ten visualizations.

* `lib/*` - perl modules that implement the bulk of the functionality of the
  system.

* `lib/MediaWords/Controller/*` - catalyst controller classes that implement
  the various pages of the web app.
  
* `lib/MediaWords/Crawler/*` - crawler implementation

* `lib/MediaWords/Crawler/Extractor.pm` - text extraction implementation

* `lib/MediaWords/DB.pm` - database connection details

* `lib/DBIx/Simple/MediaWords.pm` - local sub class of DBIx::Simple that
  Media Cloud uses for database access
  
* `lib/Bundle/MediaWords.pm` - cpan bundle with the modules used by Media Cloud

* `lib/Feed/Scrape.pm` - scrape rss/atom feeds from an html page

* `lib/MediaWords/Pager.pm` - find next page link in a web page

* `lib/MediaWords/Tagger.pm` and `Tagger/*.pm` - return a set of tags from a block
  of text

* `data/` - directory for all data files, including downloaded content and 
  support files for tagging systems
  
* `data/content/` - directory where all downloaded content is stored.  On our 
  production system, this directory has about 500G of content after
  9 months of downloading ~1500 feeds.
