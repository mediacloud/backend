Feedly Import Validation
========================

This document described how we validated the performance of the [Feedly import
module](../../lib/modules/MediaWords/ImportStories/Feedly.pm).   The purpose of the feedly import module is to use
the feedly api to backfill stories into existing feeds.  Without feedly, we can only collect feed contents from the
time we added a given feed to the system.  By using the feedly api, we can stories going back as far into the past
as feedly has data for some feed (presumably from the first time some feedly user first subscribed to the given feed).

Problem
-------

The main problem to solve with the feedly import is that we have to merge feedly stories into the existing stories
for a given medium.  If we just add all stories from feedly to the media sources, some of those stories may already
exist within the media source, so we will often end up with duplicate stories.

Metric
------

The validation metric is the precision and recall of the feedly deduping system.

This validation does not measure the degree to which feedly stories represent the full set of stories within a given
source.  It only measures how many of the feedly stories that should be added to our system get added after
deduplication (recall) and how many of the feedly stories that are added are not duplicates (precision).

Method
------

We use [mediawords_generate_feedly_import_validation.pl](../../script/mediawords_generate_feedly_import_validation.pl)
to generate feedly import results for a random sampling of feeds.  To generate this random sample, we import feeds from
a random set of 100 active feeds for which feedly has stories.  For each imported feed, we generate a random list of up
to 10 stories returned by feedly and marked as either duplicate stories or new stories.  We then randomly sort the
resulting list of stories and code the first 100 stories for precision.  For stories marked as duplicates, we score for
recall by manually reviewing the feedly imported story to the story for which was marked a duplicate.  For stories
marked as new, we score for precision by searching in our data for a story from the same media source on the same day
that includes some key word or phrase from the story title.
