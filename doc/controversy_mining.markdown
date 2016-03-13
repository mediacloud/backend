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

For implementation of media source assignment, see lookup_medium_by_url() in
[MediaWords::CM::Mine](../lib/MediaWords/CM/Mine.pm).  For implementation of media source deduplication, see
[mediawords_dedup_controversy_media.pl](../script/mediawords_dedup_controversy_media.pl).

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

For stories that we collect from RSS feeds, we assign the publish date from the feed item to the story, or the
collection date / time if there is no publish date in the RSS feed.  These dates are often not accurate to the hour but
are almost always accurate to the day.

For spidered stories, we have no RSS date, so we have guess the date using just the html of the story.  There is no
single format for including structured data about dates in html.  There are several different xml tags that various
different publishers use, many of which may indicate the date of either the whole story or of some element related
to the story (a comment, another story, the whole media source, etc).

We have a date guessing method that assigns a date based on a series of about 15 different date parsing methods,
including xml element methods like the '<meta article:published_time>' tag or other methods like a date in the url
(http://foosource.com/2016/03/05/foo.html).  The final date parsing method is simply to look for any text that looks
like a date anywhere in the text of the html.  If date parsing fails altogether, the story is assigned the date
of the first story discovered that linked to the story.

When a date is guessed, we associate a 'date_guess_method' tag with the story.  For an idea of how commonly various
methods are used by the module, here are the date guess method counts for the net neutrality controversy:

| tag                                  | count |
|--------------------------------------|-------|
| guess_by_span_published_updated_date |     3 |
| guess_by_meta_item_publish_date      |     4 |
| manual                               |    33 |
| guess_by_meta_pubdate                |    44 |
| guess_by_abbr_published_updated_date |    53 |
| guess_by_datetime_pubdate            |    61 |
| guess_by_storydate                   |    84 |
| guess_by_datatime                    |   106 |
| guess_by_meta_date                   |   195 |
| guess_by_meta_publish_date           |   217 |
| guess_by_sailthru_date               |   231 |
| guess_by_dc_date_issued              |   382 |
| guess_by_class_date                  |   451 |
| guess_by_twitter_datatime            |   465 |
| guess_by_og_article_published_time   |  1479 |
| source_link                          |  1709 |
| guess_by_url_and_date_text           |  2098 |
| merged_story_rss                     |  2110 |
| guess_by_date_text                   |  2608 |

For some stories, there is no single date that can be assigned to the page.  For instance, there is no single publish
date for a wikipedia page or the home page of an activist site.  Before guessing the date of a story, the date guessing
tries to guess whether the story is undateable by looking at the url.  For instance, urls with no path are assumed
undateable, as are urls with no numbers in the path.

When we validated this method, we found that dates guessed by some method other than guess_by_url_and_date_text (which
are almost always correct) are accurate to the day in 87% of cases.  The above numbers are from a controversy with  
30,334 total stories, 3,254 of which were marked as undeateable and 8,125 of which were guessed using an 87% accurate
method.

We also allow the user to either edit the date or mark the date as correct, in which case we add a date_confirmed
tag to the story.

For implementation of date guessing, see [MediaWords::CM::GuessDate](../lib/MediaWords/CM/GuessDate.pm).

Date Accuracy Modeling
----------------------

Problem: Even though the absolute number of misdated stories is relatively small, that small number of misdated stories
can badly distort findings for specific time slices that have a small number of stories relative to the larger
controversy.

We worked hard to make the date guessing as accurate as possible, resulting for example in only about 1,000 misdated
stories in the net neutrality debate.  But we found repeatedly in early controversies that even that small number
of misdated stories could badly distort results in weeks with small numbers just from the large number of stories
that potentially might by misdated linking in to the small week.

To mitigate this problem, we have time slice reliability modeling.  When we run a dump for a controversy, we use the
data generated from the date guessing validation to randomly perturb individual dates of the controversy and then
rerun the analysis of the most inlinked media sources for each time slice.  We then run a correlation between the
set of media source rankings for each modeling run and the unperturbed rankings and store the mean and the stddev of
the correlations (r2) between the perturbed rankings and the unperturbed ranking.  We mostly arbitrarily assign human
readable labels to each time slice according to the following rubric:

```
reliable: mean - stddev > 0.85
somewhat: mean - stddev > 0.75
not: mean - stddev <= 0.75
```

For implementation of date accuracy modeling, see [MediaWords::CM::Dump::Mine](../lib/MediaWords/CM/Dump/Mine.pm).
