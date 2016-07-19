Topics
=============

This document provides a high level overview of how the topic mapping system works and points to the pieces of
code that perform specific functions.

It will be useful to read and understand [story_processing_flow.markdown](story_processing_flow.markdown) before reading
this doc.  It is also useful to read [topic_mining.markdown](topic_mining.markdown) in conjunction with
this document.

The topic mapping system is used to generate and analyze spidered sets
of stories on some time and text pattern defined topic. The key differences
between the topic mapping system and the rest of the system are that:

* the cm uses links in the text of existing content to spider for new content
  (in general all stories in media cloud are discovered via an rss feed) and
* as the cm parses links to discover new stories, it stores those links in the
  database so that we can use them for link analysis.

The code that runs the topics spider is [MediaWords::TM::Spider](../lib/MediaWords/TM/Spider.pm).  More
information about the topic mining process is [here](topic_mining.markdown).

The code that snapshots topics and performs analysis (aggregates link counts, generates link counts,
models reliability for date guesses) is in [MediaWords::TM::Mine](../lib/MediaWords/TM/Mine.pm).  More information about
the snapshotting process is [here](snapshots.markdown).

The topic web ui is implemented in the
[MediaWords::Controller::Admin::CM](../lib/MediaWords/Controller/Admin/CM.pm) catalyst controller.

How to run a topic for development
----------------------------------------

0. If you are running on a development machine, first make sure that you have a solr instance running in supervisord.
Then run the following import data into solr from postgres and verify existence of data in solr  by searching for a
common word on the /search page.

**DO NOT RUN THIS IN PRODUCTION!**

The process for running a topic in production is the same, but without the solr import (the production
solr database will already have data).

<pre>
script/run_with_carton.sh script/mediawords_import_solr_data.pl --delete_all
</pre>

1. Go to http://localhost:3000/admin/cm (replace localhost:3000 with your mc web app).

2. Click on 'create topic' link on the right of the page.

3. Fill out the topic form with a solr query and a pattern that will return a
good number of stories within your database.

4. Check 'preview' and click submit to see a preview of the stories returned by the given
solr query and pattern.

5. Click the back button.

6. If there were not enough stories (a few hundred for a viable topic), go back to step 3.

7. If there were enough stories, uncheck 'preview' and click submit.

8. In a shell, go to your mediacloud directory and run the following, replacing <topics_id> with the
id of the newly created topic (visible in the url of the topic page after completion of step 7):

<pre>
script/run_with_carton.sh script/mediawords_mine_topic.pl --topic <topics_id> --direct_job
</pre>

9. Wait for the topic spider to complete.  This can take anywhere from an hour or so to several days.  
If you want it to complete faster, edit mediawords->cm\_spider\_iterations in mediawords.yml to some small
number (1 or 2), which will make the spider only spider out that many levels from the seed set.

10. Once the the mine has finished, run the following command and follow the instructions within the script
to dedupe the media discovered during the spidering process:

<pre>
script/run_with_carton.sh script/mediawords_dedup_topic_media.pl
</pre>

11. After all media have been deduped, run the command in step 8 again to make the miner process the stories
in the media now marked as dups.

12. Run the following to create a snapshot for the topic:

<pre>
script/run_with_carton.sh script/mediawords_snapshot_topic.pl --topic <topics_id> --direct_job
</pre>

13. That's it.  You should have a functioning topic.  Go to the topic page in step 1 and
click on the newly create topic.

Basic flow of CM
----------------

1. Search solr for a set of seed stories.

2. Add each seed set story to topic if it matches the topic regex.

3. Extract and download every link in the matching seed set stories.

4. Add to the topic each downloaded link that matches the topic
   regex.

5. Repeat 3. and 4. until no new topic links are found or the max number
   of iterations is reached.

6. Dedupe stories by duplicate media source, duplication title, or duplicate
   url.

7. Add the `<topic name>:all` tag to each story in the topic.


Tables used by CM
-----------------

* `topics` -- basic topic metadata
* `topic_stories` -- stories that are currently part of each topic
* `topic_links` -- all links from all stories within each topic
* `topic_links_cross_media` -- (view) only links between topic
   stories from different media sources
* `topic_dates` -- list of dates for custom timespans; each topic
   must include at least one pair of dates that define the outer range of date
   coverage
* `topic_seed_urls` -- list of urls to add to a topic in addition
   to those discovered by the `solr_seed_query`
* `snapshots` -- snapshots of topics to maintain consistent results
   for researchers
* `timespans` -- snapshot results partitioned by date ranges
* `snap.live_stories` -- mirror of stories only for stories in topic_stories,
   with the addition of a topics_id field'; for quicker access to stories
   in topics than is possible using the giant stories table
* `snap.*` -- tables used for snapshotting


Detailed explanation of CM process
----------------------------------

1. Write both a solr query and date range that defines the topic seed
   set as a combination of text, collection tag, and date clauses, for example
   `( sentence:trayvon AND tags_id_media:123456 AND
   publish_date:[2012-03-01T00:00:00Z TO 2012-05-01T00:00:00Z] )`.

2. Validate that this query has at most 10% false positives by searching on
   `core/search` and manually validating the first ~25 (randomly sampled)
   stories returned on `core/search` page.  Repeat 1. and 2. until a good solr
   query is found.

3. Write a regex pattern that corresponds as closely as possible to the text
   part of the solr seed query.  Any story added to the topic will have
   to match this pattern, including the stories returned by the solr seed
   query.

4. Create a row in the topics table with the above solr seed query and
   topic regex using the `core/admin/tm/create` page.
    * This basic topic metadata goes into the `topics` table.

5. Add any additional seed set urls from other sources (e.g. manual research by
   RAs, twitter links, google search results).
    * These seed set urls are generated manually and imported from CSVs into
      `topic_seed_urls` using
      `mediawords_import_topic_seed_urls.pl`.
    * The topic_seed_urls table as an `assume_match` field that, if true,
      makes the spider add every url from this regardless of whether it matches
      the topic pattern; otherwise only urls that match the pattern are
      added to the topic.

6. Run `mediawords_mine_topic.pl --topic <id>` to start the topic mining
   process. You can use the `--direct_job` option to run the mining code
   directly in process rather than sending a job off to the
   `TM/Minetopic` job.  The topic mining sets off the following
   process:

    1. If `topics.solr_seed_query_run` is `false`, the miner executes
       the `solr_seed_query` on solr and adds all of the returned stories that
       also match the topic regex to the topic.
        * These stories go into `topic_stories`.
    2. The miner downloads all additional seed set urls from (5) that do not
       already exist in the database and adds a story and `topic_story`
       for each.
    3. The miner parses all links from the extracted html from each story in
       the topic.
        * Every link extracted from a topic is added to
          `topic_links`.
    4. For each link, the miner either matches it to a the url of an existing
       story in the database or downloads it and adds it as a new story.
    5. For each story at the end point of a link from a topic story, the
       miner adds it to the topic if it matches the topic regex.
    6. The miner repeats (6.3) - (6.5) for all stories newly added to the
       topic, until no new stories are found or a maximum number of
       iterations is reached.
    7. The miner dedupes stories based on duplicate media sources (found by
       walking through the `media.dup_media_id` values), duplicate titles, and
       duplicate urls.
        * Story title and url deduping is implemented in
          `MediaWords::DBI::Stories`, `get_medium_dup_stories_by_url` and
          `get_medium_dup_stories_by_title`.

7. Manually dedupe all media associated with a topic (as each new story is
   added, a media source has to found or created for it based on the url host
   name, and often those media sources end up being duplicates, e.g.
   `articles.orlandosun.com` and `www.orlandosun.com`).  The below script
   remembers which media sources have already been reviewed for duplication at
   least once, so you will have review only media sources not previously
   reviewed.
    * media deduping is implemented in `mediawords_dedup_topic_media.pl`

8. Run `mediawords_mine_topic.pl` again if any media sources have been
   marked as duplicates in (7) to merge stories from duplicate media.

9. Run a snapshot of the topic to create a static snapshot of the data that
   can act as a stable data set for research, to generate the timespan
   network maps, and to generate reliability scores for the influential media
   list in each timespans.
    * snapshotting is implemented by `MediaWords::TM::Snapshot::snapshot_topic`

10. Review the snapshot data, performing any more manual edits (editing story and
    media names, checking dates, analyzing influential media lists for each
    timespan, and so on).

11. Redo the mine, dedup media, mine, snapshot steps any time new stories are added
    to the topic (for instance after adding more seed urls).

12. Rerun the snapshot any time the topic data has been changed and
    researchers need a new set of consistent results, new maps, or new
    reliability scores.  

Mining vs. Snapshotting
------------------

A snapshot is always required to capture new or updated data for a topic in a static snapshot.  If a user is browsing
a topic through a snapshot, even a simple media source name change will not be visible until a new snapshot
is created.  This snapshot requirement holds as well for more complex analytical data like link counts.

A mining job is only required if new data requires a spider to run, or if deduping of stories or media sources is
required.  Most often, a topic will need to mined again if any of the following happen:

* the solr query is changed in a way that will add stories to the topic;
* new urls are added to topic_seed_urls for the topic; or
* a media source in the topic is newly marked as a dup of a media source outside of the cm web app
