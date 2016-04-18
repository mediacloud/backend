Feedly Import Validation
========================

This document describes how we validated the performance of the [Feedly import
module](../../lib/modules/MediaWords/ImportStories/Feedly.pm).   The purpose of the feedly import module is to use
the feedly api to backfill stories into existing feeds.  Without feedly, we can only collect feed contents from the
time we added a given feed to the system.  By using the feedly api, we can stories going back as far into the past
as feedly has data for some feed (presumably from the first time some feedly user first subscribed to the given feed).

Problem
-------

The main problem to solve with the feedly import is that we have to merge feedly stories into the existing stories
for a given medium.  If we just add all stories from feedly to the media sources, some of those stories may already
exist within the media source, so we will often end up with duplicate stories.  The feedly import module therefore
tries to detect duplicate stories based on url and title using the story duplication detection code used by our
controversy spider.

Metric
------

The validation metric is the precision and recall of the feedly deduping system.

This validation does not measure the degree to which feedly stories represent the full set of stories within a given
source.  It only measures how many of the feedly stories that should be added to our system get added after
deduplication (recall) and how many of the feedly stories that are added are not duplicates (precision).

Method
------

We used [mediawords_generate_feedly_import_validation.pl](../../script/mediawords_generate_feedly_import_validation.pl)
to generate feedly import results for a random sampling of feeds.  To generate this random sample, we imported feeds
from a random set of 300 active feeds for which feedly returned stories.  For each imported feed, we ran the feedly
import process implemented in [lib/MediaWords/ImportStories/Feedly.pm](../../lib/MediaWords/ImportStories/Feedly.pm) to
mark which stories returned by feedly would be marked as duplicates of existing media cloud stories (and therefore
not imported) and which would be marked as new stories (and therefore imported into the database).  We then included
only up to 10 randomly selected stories from each feed in the all feed pool.  From that all feed pool, we then selected
a random sample of 100 stories marked for import and 100 stories marked as duplicates.  

For each of those 200 stories, we manually searched our database to verify whether the story was a duplicate or not and
coded the story for import or not.  To manually search our database, we examined all stories from any date matching the
full title of the feedly story, all stories in our database for the media source of the imported feed for the publish
day of the feedly story, and all stories returned as duplicates of the feedly story by our import module.

Results
-------

The feed scraping process detected 549,748 new stories for import into the media cloud database (mean = 1099, median =
2).  On a separate test run, feedly returned stories for 100 / 127 feeds.  Media Cloud currently has about 105,000
active feeds, so importing feedly stories for all of our sources would add about 91 million new stories.

The all feed pool included 321 new stories and 4500 duplicate stories.

From the coding samples, of the 100 stories marked for import, 96 of those stories did not already exist in our
database, resulting in a precision of 0.96.  Of the 100 stories marked as duplicates, 100 of those stories had
duplicate stories in our database.
