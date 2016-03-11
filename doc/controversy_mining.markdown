Controversy Mining
==================

The controversy mining code in [MediaWords::CM::Mine](../lib/MediaWords/CM/Mine.pm) follows a relatively simple process
described below but has been extensively tweaked over a few years to handle the many problems that arise when trying to
make sense of the diverse data on the open web.  This document tries to explain both the basic flow of the spider and
how it solves the problems we have encountered over the years.

Basic Spider Flow
-----------------

A controversy is defined as:

* a solr seed query, which specifies a date range, some media sets, and a text query
* a regex pattern for determining relevance
* a date range

The basic operation of the spider is:

1. Run the solr query to get an initial set of matching stories from our archive.
2. Add the urls of those stories to the spider queue.
3. For each story in the spider queue, try to match the url against an existing media cloud story.
4. If there is no match and the raw html content of the story matches the controversy pattern, create a new story.
5. If the sentence text or url of the story (existing or created) matches the regex pattern, add it to the controversy
and add all urls within the story text to the spider queue.
6. Repeat steps 3. - 6. until the spider has completed 15 complete iterations (or the max_iterations set for the
controversy).

Details
-------

The above approach is sound because of the power law of the internet.  The spider is only following outgoing links, and
linking on the web follows a power law (most links go to a small number of core sites).  So if we limit to a specific
topic by doing regex pattern matching, the spider almost always finds virtually of the sites in the topic network
defined by the starting seed set within 15 iterations.

Lots of problems arise when we try to get robust research data from the above approach, though.  Below are descriptions
of those problems and the solutions we have implemented for them.

Story Matching
--------------

Problem: Stories often do not match by the simple approach of matching urls.

The first problem with simple url matching is that many pages link to redirecting urls that eventually lead to the
story in question.  We mitigate this problem by matching on both the original url and the url that the original
url redirects to.  We also try to match to the guid that we store for our RSS crawled stories, since that guid is
sometimes an alternative url for the story.

In many cases, there are multiple, non-redirecting urls for the same story.  Some of those urls are small variations
of a common url (for example, with different '#...' anchors tagged onto the end, or with varying case).  Before matching
urls we use a lossy url normalization process that pretty aggressively trims information out of urls that is rarely
useful in distinguishing stories (for example, we remove everything after '#' and lowercase all urls).  

For the full details of our url matching, see
[MediaWords::DBI::Stories::get_medium_dup_stories_by_url](../lib/MediaWords/DBI/Stories.pm).

Even with redirect url matching and aggressive url normalization, we still often miss duplicate stories, so we also
deduplicate stories by title.  The basic approach of the title deduplication is to break the title of each story into
parts by [-:|] and look for any such part that is the sole title part for any one story and is at least 4 words long and
is not the title of a story with a path-less url.  Any story in the same media source as that story that includes that
title part becomes a duplicate.  The idea is that we often see duplicate stories not only by exact title but also in
the form of 'Trayvon Martin case to go to grand jury' vs. 'Orlando Sentinel: Trayvon Martin case to go to grand jury'.

For the full details of our title matching, see
[MediaWords::DBI::Stories::get_medium_dup_stories_by_title](../lib/MediaWords/DBI/Stories.pm).


Media Source Assignment
-----------------------

Problem: We want to do analysis of larger media sources that publish the stories, but in most web pages there is no
structured data about the publisher.

For urls that match a story already in our database, we already have a media source for the story (because our
platform assigns every rss feed we crawl to a media source).  But for spidered stories that do not match an existing
story, we need to assign the story to either an existing media source or a new one we create on the spot.

We assign stories to media sources based on the url host (for
'http://www.nytimes.com/2016/03/11/us/politics/republican-debate.html' the domain is 'www.nytimes.com').  The same
lossy url normalization algorithm is used on the medium url as is used on the urls for story matching described
above.  If a media source with the normalized url does not already exist, we create a new one.

In many cases, media sources use urls too different for the normalization algorithm to detect.  To treat those cases,
we periodically run a manual media source deduplication script that presents to a human lists of controversy media
sources with the same media url domain.  The human makes a judgment about whether media sources with the same
url domain are duplicates or not.  These media duplicate lists are then used for all future controversy spider runs
(including reruns on existing controversies, in which case stories from duplicate media sources are merged).

External Seed Sets
------------------

Problem: In some cases, the existing Media Cloud content does not provide a sufficient seed set to accurately reflect
activity around the controversy topic.

For these cases, we provide the option of adding an externally generated list of urls to seed a controversy.  Those
urls might come from manual google searches, twitter searches, or researcher curation.  When the controversy has a list
of external seed urls, those urls are simply added the spider url queue before running the spider.

Date Assignment
---------------

Problem: We need publish dates for our analysis, but it is hard and error prone to guess dates from content discovered
on the open web.
