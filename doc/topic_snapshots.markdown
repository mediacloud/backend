Snapshots
=================

topic analysis is based around the idea of a snapshot.  Snapshots store static, snapshotted data about all database
entities related to a topic.  Snapshoting a topic also generates analytical data, like link counts, that are
specific to both all stories within the topic and to specific date ranges within the topic.  The snapshoting
framework also allows access to 'live' virtual snapshots that use the same database structure but do the date range specific
analytical work on the live topic data.

The notion of snapshots evolved from the earliest version of topic, in which we did not have a web interface, but
instead just snapshoted a set of csv files each time we wanted to start analysis of a topic.  The main purpose of the
current snapshoting system is to generate a snapshot of the topic at the time of the snapshot, so that researchers can
work off of a consistent set of data while others might be cleaning the topic data and so that publications can
refer back to a static set of data that will not ever change.

Snapshot data is organized around the snapshots and timespans tables.  A topic
snapshot represents a single run of the snapshoting process.  A snapshot timespan represents a date range for analysis
within a snapshot.  So each time we run a snapshot, we generate a single row in the snapshots table and multiple rows in
the timespans table (one for each date range set for analysis in the topic and all pointing
to the single snapshot row).  

By default every topic is set to generate the following timespans:

* an overall timespan - every story regardless of date
* weekly/monthly timespans - stories within each calendar week/month within the date range of the
topic
* an overall custom date range - stories within the date range of the whole topic

A story is considered to be within some date range if it has a publication date within that date range or if it is
linked to by a story within that date range.

The basic mechanism of the snapshots is to store copies of all data relevant to a topic in snap.* postgres tables ('snap'
is a postgres schema, which acts as a separate namespace for tables). These tables are kept in a separate schema just
to make clear their function within the database and to allow naming the same as the base tables (eg. `snap.stories`).

The set of tables snapshotted at the time of each snapshot is stored in $MediaWords::TM::Snapshot::_snapshot_tables and at the
time of writing this doc includes: topic_stories, topic_links_cross_media, topic_media_codes, stories,
media, stories_tags_map, media_tags_map, tags, tag_sets.  During each snapshot, all of the fields are copied from each of
those tables along with a snapshots_id field pointing to the snapshot for which the table was snapshotted.

For example, the snap.tags table definition is:

Column        |          Type          | Modifiers
----------------------|------------------------|-----------
snapshots_id | integer                | not null
tags_id              | integer                |
tag_sets_id          | integer                |
tag                  | character varying(512) |
label                | text                   |
description          | text                   |

During the snapshot process, we also do analysis and aggregation of the data, mostly so that we only have to do it once.
This analysis work includes counting links for media sources and stories and generating link network graphs.  Unlike
the snapshotted tables above, for which we simple copy the data in the snapshotted table, for these analysis tables
we are creating new data during the snapshot that depends on the particular timespan.  

This allows us, for example, to store the inlink_count for each story consisting of just links coming from stories
within a specific date range in the snap.story_link_counts tables.

Column              |  Type   | Modifiers
---------------------------------|---------|-----------
timespans_id | integer | not null
stories_id                      | integer | not null
inlink_count                    | integer | not null
outlink_count                   | integer | not null
bitly_click_count               | integer |

At the time of this doc, we are generating the following analysis snapshot tables: medium_link_counts, story_link_counts.

In order to generate those link count tables, we generate a number of temporary tables consisting of must the stories
and media within the given date range.  These tables are prefaced with snapshot_ and include: snapshot_topic_stories,
snapshot_stories, snapshot_media, snapshot_topic_links_cross_media, snapshot_stories_tags_map, snapshot_stories_tags_map,
snapshot_tag_sets, snapshot_media_with_types.  

The snapshot process also create a snapshot_period_stories temporary table that consists only of the stories_ids of the stories
included in the timespan currently being snapshoted.  The _link_counts tables are generated with queries that ultimately
join snapshot_period_stories to other snapshot_ tables to generate the necessary counts for only the specific timespan.

It is important to know about the snapshot_ tables for two reasons.  First, topic mapper related queries will appear
in the running queries list of the server that include these tables, which are not in the static schema definition
in script/mediawords.sql.  A downside of the use of these temporary tables is that these queries can be difficult
to optimize because they cannot be explained in a separate session with psql.  Instead, you have to embed an explain
query in the code that creates and uses the temporary tables.

More importantly, we use these snapshot_ tables as an abstraction interface for querying topic data both lived and
snapshoted data.  We use this abstraction layer so that we can allow web app or api code to have access to the snapshot
tables without having to query the snap.* tables, which are traditional tables that are expensive to update in real time.
For details about how to query the snapshot tables, see [MediaWords::TM::Snapshot](../lib/MediaWords/TM/Snapshot.pm).
