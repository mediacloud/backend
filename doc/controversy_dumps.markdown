Controversy Dumps
=================

Controversy analysis is based around the idea of a dump.  Dumps store static, snapshotted data about all database
entities related to a controversy.  Dumping a controversy also generates analytical data like link counts specific to
both all stories within the controversy and to specific date ranges within the controversy.  The dumping framework also
allows access to 'live' virtual dumps that use the same database structure but do the date range specific analytical
work on the live controversy data.

The notion of dumps evolved from the earliest version of controversy, in which we did not have a web interface, but
instead just dumped a set of csv files each time we wanted to start analysis of a controversy.  The main purpose of the
current dumping system is to generate a snapshot of the controversy at the time of the dump, so that researchers can
work off of a consistent set of data while others might be cleaning the controversy data and so that publications can
refer back to a static set of data that will not ever change.

Controversy dump data is organized around the controversy_dumps and controversy_dump_time_slices tables.  A controversy
dump represents a single run of the dumping process.  A controversy dump time slice represents a date range for analysis
within a dump.  So each time we run a dump, we generate a single row in the controversy_dumps table and multiple rows in
the controversy_dump_time_slices table (one for each date range set for analysis in the controversy and all pointing
to the single controversy_dump row).  

By default every controversy is set to generate the following time slices:

* an overall time slice - every story regardless of date
* weekly/monthly time slices - stories within each calendar week/month within the date range of the
controversy
* an overall custom date range - stories within the date range of the whole controversy

A story is considered to be within some date range if it has a publication date within that date range or if it is
linked to by a story within that date range.

The basic mechanism of the dumps is to store copies of all data relevant to a controversy in cd.* postgres tables ('cd'
is a postgres schema, which acts as a separate namespace for tables). The set of tables snapshotted at the time of each
dump is stored in $MediaWords::CM::Dump::_snapshot_tables and at the time of writing this doc includes:
controversy_stories, controversy_links_cross_media, controversy_media_codes, stories, media, stories_tags_map,
media_tags_map, tags, tag_sets.  During each dump, all of the fields are copied from each of those tables along with a
controversy_dumps_id field pointing to the dump for which the table was snapshotted.

For example, the cd.tags table definition is:

Column        |          Type          | Modifiers
----------------------|------------------------|-----------
controversy_dumps_id | integer                | not null
tags_id              | integer                |
tag_sets_id          | integer                |
tag                  | character varying(512) |
label                | text                   |
description          | text                   |

During the dump process, we also do analysis and aggregation of the data, mostly so that we only have to do it once.
This analysis work includes counting links for media sources and stories and generating link network graphs.  Unlike
the snapshotted tables above, for which we simple copy the data in the snapshotted table, for these analysis tables
we are creating new data during the dump that depends on the particular time slice.  

This allows us, for example, to store the inlink_count for each story consisting of just links coming from stories
within a specific date range in the cd.story_link_counts tables.

Column              |  Type   | Modifiers
---------------------------------|---------|-----------
controversy_dump_time_slices_id | integer | not null
stories_id                      | integer | not null
inlink_count                    | integer | not null
outlink_count                   | integer | not null
bitly_click_count               | integer |

At the time of this doc, we are generating the following analysis dump tables: medium_link_counts, story_link_counts.

In order to generate those link count tables, we generate a number of temporary tables consisting of must the stories
and media within the given date range.  These tables are prefaced with dump_ and include: dump_controversy_stories,
dump_stories, dump_media, dump_controversy_links_cross_media, dump_stories_tags_map, dump_stories_tags_map,
dump_tag_sets, dump_media_with_types.  

The dump process also create a dump_period_stories temporary table that consists only of the stories_ids of the stories
included in the time slice currently being dumped.  The _link_counts tables are generated with queries that ultimately
join dump_period_stories to other dump_ tables to generate the necessary counts for only the specific time slice.

It is important to know about the dump_ tables for two reasons.  First, controversy mapper related queries will appear
in the running queries list of the server that include these tables, which are not in the static schema definition
in script/mediawords.sql.  A downside of the use of these temporary tables is that these queries can be difficult
to optimize because they cannot be explained in a separate session with psql.  Instead, you have to embed an explain
query in the code that creates and uses the temporary tables.

More importantly, we use these dump_ tables as an abstraction interface for querying controversy data both lived and
dumped data.  We use this abstraction layer so that we can allow web app or api code to have access to the dump
tables without having to query the cd.* tables, which are traditional tables that are expensive to update in real time.
For details about how to query the dump tables, see [MediaWords::CM::Dump](../lib/MediaWords/CM/Dump.pm).
