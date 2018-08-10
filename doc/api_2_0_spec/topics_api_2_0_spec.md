<!-- MEDIACLOUD-TOC-START -->

Table of Contents
=================

   * [Overview](#overview)
      * [Media Cloud Crawler and Core Data Structures](#media-cloud-crawler-and-core-data-structures)
      * [Topic Data Structures](#topic-data-structures)
      * [Snapshots, Timespans, and Foci](#snapshots-timespans-and-foci)
      * [Paging](#paging)
      * [Examples](#examples)
      * [Permissions](#permissions)
   * [Topics](#topics)
      * [topics/create (POST)](#topicscreate-post)
         * [Query Parameters](#query-parameters)
         * [Input Description](#input-description)
         * [Example](#example)
      * [topics/&lt;topics_id&gt;/update (PUT)](#topicstopics_idupdate-put)
         * [Query Parameters](#query-parameters-1)
         * [Input Description](#input-description-1)
         * [Example](#example-1)
      * [topics/&lt;topics_id&gt;/reset (PUT)](#topicstopics_idreset-put)
         * [Query Parameters](#query-parameters-2)
         * [Input Description](#input-description-2)
         * [Example](#example-2)
      * [topics/&lt;topics_id&gt;/spider (POST)](#topicstopics_idspider-post)
         * [Query Parameters](#query-parameters-3)
         * [Output Description](#output-description)
         * [Example](#example-3)
      * [topics/&lt;topics_id&gt;/spider_status](#topicstopics_idspider_status)
         * [Query Parameters](#query-parameters-4)
         * [Output Description](#output-description-1)
         * [Example](#example-4)
      * [topics/list](#topicslist)
         * [Query Parameters](#query-parameters-5)
         * [Output Description](#output-description-2)
         * [Example](#example-5)
      * [topics/single/&lt;topics_id&gt;](#topicssingletopics_id)
         * [Query Parameters](#query-parameters-6)
         * [Output Description](#output-description-3)
         * [Example](#example-6)
   * [Permissions](#permissions-1)
      * [topics/permissions/user/list](#topicspermissionsuserlist)
         * [Query Parameters](#query-parameters-7)
         * [Output Description](#output-description-4)
         * [Example](#example-7)
      * [topics/&lt;topics_id&gt;/permissions/list](#topicstopics_idpermissionslist)
         * [Query Parameters](#query-parameters-8)
         * [Output Description](#output-description-5)
         * [Example](#example-8)
      * [topics/&lt;topics_id&gt;/permissions/update (PUT)](#topicstopics_idpermissionsupdate-put)
         * [Query Parameters](#query-parameters-9)
         * [Input Description](#input-description-3)
         * [Output Description](#output-description-6)
         * [Example](#example-9)
   * [Stories](#stories)
      * [topics/&lt;topics_id&gt;/stories/list](#topicstopics_idstorieslist)
         * [Query Parameters](#query-parameters-10)
         * [Output Description](#output-description-7)
      * [topics/&lt;topics_id&gt;/stories/links](#topicstopics_idstorieslinks)
         * [Query Parameters](#query-parameters-11)
         * [Output Description](#output-description-8)
         * [Example](#example-10)
      * [topics/&lt;topics_id&gt;/stories/facebook](#topicstopics_idstoriesfacebook)
         * [Query Parameters](#query-parameters-12)
         * [Output Description](#output-description-9)
         * [Example](#example-11)
      * [topics/&lt;topics_id&gt;/stories/count](#topicstopics_idstoriescount)
         * [Query Parameters](#query-parameters-13)
         * [Output Description](#output-description-10)
         * [Example](#example-12)
   * [Sentences](#sentences)
      * [topics/&lt;topics_id&gt;/sentences/count](#topicstopics_idsentencescount)
   * [Media](#media)
      * [topics/&lt;topics_id&gt;/media/list](#topicstopics_idmedialist)
         * [Query Parameters](#query-parameters-14)
         * [Output Description](#output-description-11)
         * [Example](#example-13)
      * [topics/&lt;topics_id&gt;/media/map](#topicstopics_idmediamap)
         * [Query Parameters](#query-parameters-15)
         * [Output Description](#output-description-12)
         * [Example](#example-14)
   * [Word Counts](#word-counts)
      * [topics/&lt;topics_id&gt;/wc/list](#topicstopics_idwclist)
   * [Foci](#foci)
      * [Focal Techniques](#focal-techniques)
         * [Focal Technique: Boolean Query](#focal-technique-boolean-query)
         * [Focal Technique: Similar Stories](#focal-technique-similar-stories)
      * [topics/&lt;topics_id&gt;/focal_set_definitions/create (POST)](#topicstopics_idfocal_set_definitionscreate-post)
         * [Query Parameters](#query-parameters-16)
         * [Input Description](#input-description-4)
         * [Example](#example-15)
      * [topics/&lt;topics_id&gt;/focal_set_definitions/&lt;focal_set_definitions_id&gt;/update (PUT)](#topicstopics_idfocal_set_definitionsfocal_set_definitions_idupdate-put)
         * [Query Parameters](#query-parameters-17)
         * [Input Parameters](#input-parameters)
         * [Example](#example-16)
      * [topics/&lt;topics_id&gt;/focal_set_definitions/&lt;focal_set_definitions_id&gt;/delete (PUT)](#topicstopics_idfocal_set_definitionsfocal_set_definitions_iddelete-put)
         * [Query Parameters](#query-parameters-18)
         * [Output Description](#output-description-13)
         * [Example](#example-17)
      * [topics/&lt;topics_id&gt;/focal_set_definitions/list](#topicstopics_idfocal_set_definitionslist)
         * [Query Parameters](#query-parameters-19)
         * [Output Description](#output-description-14)
         * [Example](#example-18)
      * [topics/&lt;topics_id&gt;/focal_sets/list](#topicstopics_idfocal_setslist)
         * [Query Parameters](#query-parameters-20)
         * [Output Description](#output-description-15)
         * [Example](#example-19)
      * [topics/&lt;topics_id&gt;/focus_definitions/create (POST)](#topicstopics_idfocus_definitionscreate-post)
         * [Query Parameters](#query-parameters-21)
         * [Input Description](#input-description-5)
         * [Example](#example-20)
      * [topics/&lt;topics_id&gt;/focus_definitions/&lt;focus_definitions_id&gt;/update (PUT)](#topicstopics_idfocus_definitionsfocus_definitions_idupdate-put)
         * [Query Parameters](#query-parameters-22)
         * [Input Description](#input-description-6)
         * [Example](#example-21)
      * [topics/&lt;topics_id&gt;/focus_definitions/&lt;focus_definitions_id&gt;/delete (PUT)](#topicstopics_idfocus_definitionsfocus_definitions_iddelete-put)
         * [Query Parameters](#query-parameters-23)
         * [Output Description](#output-description-16)
         * [Example](#example-22)
      * [topics/&lt;topics_id&gt;/focus_definitions/list](#topicstopics_idfocus_definitionslist)
         * [Query Parameters](#query-parameters-24)
         * [Output Description](#output-description-17)
         * [Example](#example-23)
      * [topics/&lt;topics_id&gt;/foci/list](#topicstopics_idfocilist)
         * [Query Parameters](#query-parameters-25)
         * [Ouput Description](#ouput-description)
         * [Example](#example-24)
      * [Story Similarity Models](#story-similarity-models)
         * [topics/&lt;topics_id&gt;/similarity_models/preview (POST)](#topicstopics_idsimilarity_modelspreview-post)
            * [Required role](#required-role)
            * [Input Description](#input-description-7)
            * [Output Description](#output-description-18)
               * [Sample model was generated and evaluation stories were run against it](#sample-model-was-generated-and-evaluation-stories-were-run-against-it)
               * [An error has occurred](#an-error-has-occurred)
            * [Example](#example-25)
         * [topics/&lt;topics_id&gt;/similarity_models/create (POST)](#topicstopics_idsimilarity_modelscreate-post)
            * [Required role](#required-role-1)
            * [Input Description](#input-description-8)
            * [Output Description](#output-description-19)
               * [Model was generated and stored](#model-was-generated-and-stored)
               * [An error has occurred](#an-error-has-occurred-1)
            * [Example](#example-26)
         * [topics/&lt;topics_id&gt;/similarity_models/list (GET)](#topicstopics_idsimilarity_modelslist-get)
            * [Required role](#required-role-2)
            * [Output Description](#output-description-20)
               * [Model was generated and stored](#model-was-generated-and-stored-1)
               * [An error has occurred](#an-error-has-occurred-2)
            * [Example](#example-27)
   * [Snapshots](#snapshots)
      * [topics/&lt;topics_id&gt;/snapshots/generate (POST)](#topicstopics_idsnapshotsgenerate-post)
         * [Query Parameters](#query-parameters-26)
         * [Input Description](#input-description-9)
         * [Output Description](#output-description-21)
         * [Example](#example-28)
      * [topics/&lt;topics_id&gt;/snapshots/generate_status](#topicstopics_idsnapshotsgenerate_status)
         * [Query Parameters](#query-parameters-27)
         * [Input Description](#input-description-10)
         * [Output Description](#output-description-22)
         * [Example](#example-29)
      * [topics/&lt;topics_id&gt;/snapshots/list](#topicstopics_idsnapshotslist)
         * [Query Paramaters](#query-paramaters)
         * [Output Description](#output-description-23)
         * [Example](#example-30)
      * [topics/&lt;topics_id&gt;/snapshots/&lt;snapshots_id&gt;/word2vec_model/&lt;models_id&gt; (GET)](#topicstopics_idsnapshotssnapshots_idword2vec_modelmodels_id-get)
         * [Required role](#required-role-3)
         * [Output Description](#output-description-24)
            * [Model was fetched](#model-was-fetched)
            * [Failed to fetch the model](#failed-to-fetch-the-model)
         * [Example](#example-31)
   * [Timespans](#timespans)
      * [topics/&lt;topics_id&gt;/timespans/list](#topicstopics_idtimespanslist)
         * [Query Parameters](#query-parameters-28)
         * [Output Description](#output-description-25)
         * [Example](#example-32)

----
<!-- MEDIACLOUD-TOC-END -->


# Overview

This document described the Media Cloud Topics API.  The Topics API is a subset of the larger Media Cloud API.  The Topics API provides access to data about Media Cloud Topics and related data.  For a fuller understanding of Media Cloud data structures and for information about *Authentication*, *Request Limits*, the API *Python Client*, and *Errors*, see the documentation for the main [link: main api] Media Cloud API.

The topics API is currently under development and is available only to Media Cloud team members and select beta testers.  Email us at info@mediacloud.org if you would like to beta test the Topics API.

A *topic* currently may be created only by the Media Cloud team, though we occasionally run topics for external researchers.

## Media Cloud Crawler and Core Data Structures

The core Media Cloud data are stored as *media*, *feeds*, and *stories*.

A *medium* (or *media source*) is a publisher, which can be a big mainstream media publisher like the New York Times, an
activist site like fightforthefuture.org, or even a site that does not publish regular news-like stories, such as Wikipedia.

A *feed* is a syndicated feed (RSS, RDF, ATOM) from which Media Cloud pulls stories for a given *media source*.  A given
*media source* may have anywhere from zero *feeds* (in which case we do not regularly crawl the site for new content) up
to hundreds of feeds (for a site like the New York Times to make sure we collect all of its content).

A *story* represents a single published piece of content within a *media source*.  Each *story* has a unique URL within
a given *media source*, even though a single *story* might be published under multiple urls.  Media Cloud tries
to deduplicate stories by title.

The Media Cloud crawler regularly downloads every *feed* within its database and parses out all URLs from each *feed*.
It downloads every new URL it discovers and adds a *story* for that URL, as long as the story is not a duplicate for
the given *media source*.  The Media Cloud archive consists primarily of *stories* collected by this crawler.

## Topic Data Structures

A Media Cloud *topic* is a set of stories relevant to some subject.  The topic spider starts by searching for a
set of stories relevant to the story within the Media Cloud archive and then spiders URLs from those
stories to find more relevant stories, then iteratively repeats the process 15 times.

After the spidering is complete, a *topic* consists of a set of relevant *stories*, *links* between those stories, the
*media* that published those *stories*, and social media metrics about the *stories* and *media*.  The various topics /
end points provide access to all of this raw data as well as various of various analytical processes applied to this
data.

## Snapshots, Timespans, and Foci

Each *topic* is viewed through one of its *snapshots*.  A *snapshot* is static dump of all data from a topic at
a given point in time.  The data within a *snapshot* will never change, so changes to a *topic* are not visible
until a new *snapshot* is made.

Within a *snapshot*, data can be viewed overall, or through some combination of a *focus* and a *timespan*.

A *focus* consists of a subset of stories within a *topic* defined by some user configured *focal technique*.  For
example, a 'trump' *focus* within a 'US Election' *topic* would be defined using the 'Boolean Query' *focal technique*
as all stories matching the query 'trump'.  Each individual *focus* belongs to exactly one *focal set*.  A *focal set*
provides a way of collecting together *foci* for easy comparison to one another.

A *timespan* displays the *topic* as if it exists only of stories either published within the date range of the
*timespan* or linked to by a story published within the date range of the *timespan*.

*Topics*, *snapshots*, *foci*, and *timespans* are strictly hierarchical.  Every *snapshot* belongs to a single
*topic*.  Every *focus* belongs to a single *snapshot*, and every *timespan* belongs to either a single *focus* or the
null *focus*.  Specifying a *focus* implies the parent *snapshot* of that *focus*.  Specifying a *timespan* implies the
parent *focus* (and by implication the parent *snapshot*), or else the null *focus* within the parent *snapshot*.

* topic
  * snapshot
    * focus
      * timespan

Every URL that returns data from a *topic* accepts optional *spanshots_id*, *timespans_id*, and *foci_id* parameters.

If no *snapshots_id* is specified, the call returns data from the latest *snapshot* generated for the *topic*.  If no
*timespans_id* is specified, the call returns data from the overall *timespan* of the given *snapshot* and *focus*.  If
no *foci_id* is specified, the call assumes the null *focus*.  If multiple of these parameters are specified,
they must point to the same *topic* / *snapshot* / *focus* / *timespan* or an error will be returned (for instance, a
call that specifies a *snapshots_id* for a *snapshot* in a *topic* different from the one specified in the URL, an error
will be returned).


## Paging

For calls that support paging, each URL supports a *limit* parameter and a *link_id* parameter.  For these calls, only
*limit* results will be returned at a time, and a set of *link_ids* will be returned along with the results.  To get the
current set of results again, or the previous or next page of results, call the same end point with only the *key* and
*link_id* parameters. The *link_id* parameter includes state that remembers all of the parameters from the original
call.

For example, the following is a paged response:

```json
{
    "stories":
    [
        {
            "stories_id": 168326235,
            "media_id": 18047,
            "collect_date": "2013-10-26 09:25:39",
            "publish_date": "2012-10-24 16:09:26",
            "inlink_count": 531,
            "language": "en",
            "title": "Donald J. Trump (realDonaldTrump) on Twitter",
            "url": "https://twitter.com/realDonaldTrump",
            "outlink_count": 0,
            "guid": "https://twitter.com/realDonaldTrump"
        }
    ],
    "link_ids":
    {
        "current": 123456,
        "previous": 456789,
        "next": 789123
    }
}
```

After receiving that response, you can use the following URL with no other parameters to fetch the next page of results:

`https://api.mediacloud.org/api/v2/topics/1/stories/list?link_id=789123`

When the system has reached the end of the results, it will return an empty list and a null 'next' *link_id*.

*link_ids* are persistent — they can be safely used to refer to a given result forever (for instance, as an identifier for a link shortener).

## Examples

The section for each end point includes an example call and response for that end point.  For end points that return multiple results, we generally only show a single result (for instance a single story) for the sake of documentation brevity.  All *Input* examples are JSON documents.

## Permissions

The topics API assigns read, write, and admin permissions to individual users.  Read permission allows the given user to view all data within the topic.  Write permission grants read permission and also allows the user to perform all operations on the topic -- including spidering, snapshotting, and merging — other editing permissions.  Admin permission grants write permission and also allows all the user to edit the permissions for the topic.

Each topic also has an 'public' flag.  If that flag is set to true, then all users will have implicit read permission for that topic.

Permssions for the authenticated user for a given topic are included in the topics/list and topics/single calls (note that a given topic will not be visible in either call if the authenticated user does not have read permission for it).  Other calls to list and read permissions are available from the permissions/ end points.

# Topics

Topics are collections of stories within some date range that match some pattern indicating that they belong to some topic.  Topics both stories matched from crawled Media Cloud content and stories discovered by spidering out from the links of those matched stories. For more information about topics and how they are generated, see:

http://cyber.law.harvard.edu/publications/2013/social_mobilization_and_the_networked_public_sphere

A single topic is the umbrella object that represents the whole topic.  A snapshot
is a frozen version of the data within a topic that keeps a consistent view of a topic
for researchers and also includes analytical results like link counts.  A timespan
represents the set of stories active in a topic within a given date range.  Every timespan belongs to a snapshot.

Topic data can be used to search stories and media sources as well.  Use the
timespans_id param to list the media sources within a given timespan.  See the documentation for Solr pseudo queries for documentation of how to
query for stories within a topic.

## `topics/create` (POST)

`https://api.mediacloud.org/api/v2/topics/create`

Create and return a new *topic*.

### Query Parameters

(no parameters)

### Input Description

The topics/create call accepts as input the following fields described in the Output Description of the topics/list call: name, solr_seed_query, description, max_iterations, start_date, end_date, is_public, is_logogram, ch_monitor_id, twitter_topics_id, media_ids, media_tags_ids, max_stories, is_story_index_ready. Required fields are: name, solr_seed_query, description, start_date, end_date, media_ids and media_tags_ids.  Either media_ids or media_tags_ids must be included and not be an empty list.

### Example

Create a new topic:

`https://api.mediacloud.org/api/v2/topics/create`

Input:

```json
{
    "name": "immigration 2015",
    "description": "immigration coverage during 2015",
    "solr_seed_query": "immigration AND (+publish_date:[2016-01-01T00:00:00Z TO 2016-06-15T23:59:59Z]) AND tags_id_media:8875027",
    "max_iterations": 15,
    "start_date": "2015-01-01",
    "end_date": "2015-12-31",
    "is_public": 1,
    "is_logogram": 0,
    "is_story_index_ready": 0,
    "media_tags_ids": [ 123 ],
    "max_stories": 50000
}
```
Response:

```json
{
  "topics":
  [
    {
      "topics_id": 1390,
      "name": "immigration 2015",
      "description": "immigration coverage during 2015",
      "pattern": "[[:<:]]immigration",
      "solr_seed_query": "immigration AND (+publish_date:[2016-01-01T00:00:00Z TO 2016-06-15T23:59:59Z]) AND tags_id_media:8875027",
      "max_iterations": 15,
      "start_date": "2015-01-01",
      "end_date": "2015-12-31",
      "state": "created but not queued",
      "is_public": 1,
      "is_story_index_ready": 0,
      "max_stories": 50000,
      "job_queue": "public",
      "media_tags":
      [
          {
              "tags_id": 123,
              "topics_id": 1390,
              "tag": "us_msm",
              "label": "US Mainstream Media",
              "description": "major US mainstream media sources"
          }
      ]
   }
  ]
}
```

## `topics/<topics_id>/update` (PUT)

`https://api.mediacloud.org/api/v2/topics/<topics_id>/update`

Edit an existing *topic*.

This api call will generate an error if update attempts to remove existing dates, media sources, or media source tags
from a topic that has spidered content or has a currently active spidering job.   If the solr seed query, dates, media
sources, or media source tags are updated (without generating an error), all impacted stories will be marked for
respidering during the next spidering run.

Editing a query is allowed for a topic that has already started spidering, but editing a query to reduce its scope
will not remove any stories from the existing topic and so will likely result in non-sensical results.

### Query Parameters

(no parameters)

### Input Description

Accepts the same input as the topics/create call.

### Example

Edit the 'immigration 2015' topic.

`https://api.mediacloud.org/api/v2/topics/1390/update`

Input:

```json
{
    "name": "immigration coverage in 2015"
}
```

Response:

```json
{
  "topics":
  [
    {
      "topics_id": 1390,
      "name": "immigration coverage in 2015",
      "description": "immigration coverage during 2015",
      "pattern": "[[:<:]]immigration",
      "solr_seed_query": "immigration AND (+publish_date:[2016-01-01T00:00:00Z TO 2016-06-15T23:59:59Z]) AND tags_id_media:8875027",
      "max_iterations": 15,
      "start_date": "2015-01-01",
      "end_date": "2015-12-31",
      "state": "queued",
      "is_public": 1,
      "media_tags":
      [
          {
              "tags_id": 123,
              "topics_id": 1390,
              "tag": "us_msm",
              "label": "US Mainstream Media",
              "description": "major US mainstream media sources"
          }
      ]
   }
  ]
}
```

## topics/<topics_id>/reset (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/reset`

Delete all existing stories, links, and seed urls from an existing *topic*.  Set the topic state to
'created but not queued' and the message to null.

This call should be used with caution.  After executing this call, no stories or links will remain in the *topic*, so
the *topic* will need to be entirely respidered before another snapshot is made.  Data in existing snapshots will
not be impacted in any way by this call.

This call will return an error if it is run on a *topic* with a state of 'running'.

### Query Parameters

(no parameters)

### Input Description

(no input)

### Example

Reset the 'immigration 2015' topic.

`https://api.mediacloud.org/api/v2/topics/1390/reset`

Response:

```json
{
  "success": 1
}
```

## `topics/<topics_id>/spider` (POST)

`https://api.mediacloud.org/api/v2/topics/<topics_id>/spider`

Start a topic spidering job.

Topic spidering is asynchronous.  Once the topic has started spidering, you cannot start another spidering job until the current one is complete. A call to this end point when a 'running' or 'queued' job already exists for the given topic
will just return the state of the existing job.

### Query Parameters

(no parameters)

### Output Description

The call returns a `job_state` record with information about the state of the queued spidering job.

### Example

Start a topic spider for the 'U.S. 2016 Election' topic:

`https://api.mediacloud.org/api/v2/topics/spider`

Input:

```json
{ "topics_id": 1404 }
```

Response:

```json
{
    "job_state":
        {
            "topics_id": 1404,
            "job_states_id": 1,
            "last_updated": "2017-01-26 14:27:04.781095",
            "message": null,
            "state": "queued"
        }
}
```


## `topics/<topics_id>/spider_status`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/spider_status`

Get a list all spidering jobs started for this topic.

### Query Parameters

| Parameter | Default | Notes |
|-|-|
| topics_id | (required) | topic id |


### Output Description

| Field    | Description                              |
| -------- | ---------------------------------------- |
| state | one of queued, running, completed, or error |
| message | more detailed message about the job state |
| last_updated | date of last state change |
| topics_id | id of media being scraped |

### Example

`https://api.mediacloud.org/api/v2/topics/1404/spider_status`

Response:

```json
{
    "job_states": [
        {
            "topics_id": 1404,
            "job_states_id": 1,
            "last_updated": "2017-01-26 14:27:04.781095",
            "message": null,
            "state": "queued"
        }
    ]
}
```


## `topics/list`

`https://api.mediacloud.org/api/v2/topics/list`

The topics/list call returns a simple list of topics available in Media Cloud.  The call will only return topics for
which the calling user has read or higher permissions.

The topics/list call is is only call that does not include a topics_id in the URL.

### Query Parameters

| Parameter | Default | Notes |
|-|-|-|
| name | null | return only topics with a name including the parameter value |
| public | null | return only topics for which is_public is true |
| limit | 20 | number of topics to return for each call |

Standard parameters accepted: link_id.

### Output Description

| Field               | Description                              |
| ------------------- | ---------------------------------------- |
| topics_id           | topic id                                 |
| name                | human readable label                     |
| pattern             | regular expression derived from Solr query |
| solr_seed_query     | Solr query used to generate seed stories |
| solr_seed_query_run | boolean indicating whether the Solr seed query has been run to seed the topic |
| description         | human readable description               |
| max_iterations      | maximum number of iterations for spidering |
| start_date          | start of date range for topic            |
| end_date            | end of date range for topic              |
| state               | the current status of the spidering process |
| message             | last error message generated by the spider, if any |
| is_public           | flag indicating whether this topic is readable by all authenticated users |
| is_logogram         | flag indicating whether this topic uses a query in a logogram language |
| is_story_index_ready | flag indicating whether this topic has been confirmed by the user to be ready for running on the story index|
| user_permission     | permission for user submitting the API request: 'read', 'write', 'admin', or 'none' |
| queue               | which job pool the topic runs in -- 'mc' for internal media cloud jobs and 'public' for public jobs |
| max_stories         | max number of stories allowed in the topic |
| owners              | list of users with 'admin' permissions for the topic |

### Example

Fetch all topics in Media Cloud:

`https://api.mediacloud.org/api/v2/topics/list`

Response:

```json
{
    "topics":
    [
        {
            "topics_id": 672,
            "name": "network neutrality",
            "patern": "[[:<:]]net.*neutrality",
            "solr_seed_query": "net* and neutrality and +tags_id_media:(8875456 8875460 8875107 8875110 8875109 8875111 8875108 8875028 8875027 8875114 8875113 8875115 8875029 129 2453107 8875031 8875033 8875034 8875471 8876474 8876987 8877928 8878292 8878293 8878294 8878332) AND +publish_date:[2013-12-01T00:00:00Z TO 2015-04-24T00:00:00Z]",
            "solr_seed_query_run": 1,
            "description": "network neutrality",
            "max_iterations": 15,
            "start_date": "2013-12-01",
            "end_date": "2015-04-24",
            "state": "ready",
            "error_message": "",
            "is_public": 0,
            "is_logogram": 0,
            "is_logogram": 0,
            "is_story_index_ready": 1,
            "user_permission": "admin",
            "queue": "mc",
            "max_stories": 100000,
            "owners":
            [
                {
                    "auth_users_id": 1,
                    "email": "hroberts@cyber.law.harvard.edu",
                    "full_name": "Hal Roberts",
                    "topics_id": 672,
                }
            ]
        }
    ],
    "link_ids":
    {
        "current": 123456,
        "previous": 456789,
        "next": 789123
    }


}
```

## `topics/single/<topics_id>`

`https://api.mediacloud.org/api/v2/topics/single/<topics_id>`

The topics/single call returns a single topic, if the calling user has permission to read that topic.

### Query Parameters

(no parameters)

### Output Description

(see topics/list)

### Example

Fetch a single topic:

`https://api.mediacloud.org/api/v2/topics/single/672`

Response:

```json
{
    "topics":
    [
        {
            "topics_id": 672,
            "name": "network neutrality",
            "patern": "[[:<:]]net.*neutrality",
            "solr_seed_query": "net* and neutrality and +tags_id_media:(8875456 8875460 8875107 8875110 8875109 8875111 8875108 8875028 8875027 8875114 8875113 8875115 8875029 129 2453107 8875031 8875033 8875034 8875471 8876474 8876987 8877928 8878292 8878293 8878294 8878332) AND +publish_date:[2013-12-01T00:00:00Z TO 2015-04-24T00:00:00Z]",
            "solr_seed_query_run": 1,
            "description": "network neutrality",
            "max_iterations": 15,
            "start_date": "2013-12-01",
            "end_date": "2015-04-24",
            "state": "ready",
            "error_message": "",
            "public": 0,
            "user_permission": "admin",
            "queue": "mc",
            "max_stories": 100000,
            "owners":
            [
                {
                    "auth_users_id": 1,
                    "email": "hroberts@cyber.law.harvard.edu",
                    "full_name": "Hal Roberts",
                    "topics_id": 672,
                }
            ]
        }
    ]
}
```

# Permissions

## `topics/permissions/user/list`

`https://api.mediacloud.org/api/v2/topics/permissions/user/list`

List all permissions assigned to the authenticated user for all topics.  This list includes only permissions granted specifically to this user.  Topics available for reading through the 'public' flag are not included in this list.

### Query Parameters

(no parameters)

### Output Description

| Field      | Description                              |
| ---------- | :--------------------------------------- |
| email      | email of user granted permission         |
| topics_id  | id of topic to which permission is granted |
| permission | 'read', 'write', or 'admin'              |

### Example

List all permissions belonging to the authenticated user:

`https://api.mediacloud.org/api/v2/topics/permissions/user/list`

Response:

```json
{
  "permissions":
  [
    {
      "email": "hroberts@cyber.law.harvard.edu",
      "topics_id": 1390,
     "permission": "admin"
    }
  ]
}
```

## `topics/<topics_id>/permissions/list`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/permissions/list`

List all permissions for the given topic.

### Query Parameters

(no parameters)

### Output Description

(see permissions/user/list)

### Example

List all permissions belonging to the given topic:

`https://api.mediacloud.org/api/v2/topics/1394/permissions/list`

Response:

```json
{
  "permissions":
  [
    {
      "email": "hroberts@cyber.law.harvard.edu",
      "topics_id": 1390,
     "permission": "admin"
    },
   {
      "email": "foo@foo.bar",
      "topics_id": 1390,
     "permission": "read"
    }

  ]
}
```

## `topics/<topics_id>/permissions/update` (PUT)

`https://api.mediacloud.org/api/v2/topics/<topics_id>/permissions/update`

Update permissions for a given user to a given topic.

### Query Parameters

(no parameters)

### Input Description

| Field      | Description                              |
| ---------- | ---------------------------------------- |
| email      | email of user whose permission is to be updated |
| permission | 'read', 'write', 'admin', or 'none'      |

 Only one permission can exist for a given topic for a given user.  Specify 'none' to remove all permissions for the given topic for the given user.

### Output Description

On success, the new permission is returned in the same format as the permissions/list_users end point.  On failure, an error is returned.

### Example

Update the permissions for a given user for a given topic:

`https://api.mediacloud.org/api/v2/topics/<topics_id>/permissions/update`

Input:

```json
{
  "email": "foo@foo.bar",
  "permission": "read"
}
```



Response:

```json
{
  "permissions":
  [
   {
      "email": "foo@foo.bar",
      "topics_id": 1390,
     "permission": "read"
    }
  ]
}
```



# Stories

## `topics/<topics_id>/stories/list`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/stories/list`

The stories list call returns stories in the topic.

### Query Parameters

| Parameter            | Default | Notes                                    |
| -------------------- | ------- | ---------------------------------------- |
| q                    | null    | if specified, return only stories that match the given Solr query |
| sort                 | inlink  | possible values: `inlink`, `facebook`, `twitter` |
| stories_id           | null    | return only stories matching these stories_ids |
| link_to_stories_id   | null    | return only stories from other media that link to the given stories_id |
| link_from_stories_id | null    | return only stories from other media that are linked from the given stories_id |
| link_to_media_id     | null    | return only stories that link to stories in the given media |
| link_from_media_id   | null    | return only stories that are linked from stories in the given media_id |
| media_id             | null    | return only stories belonging to the given media_ids |
| limit                | 20      | return the given number of stories       |
| link_id              | null    | return stories using the paging link     |

The call will return an error if more than one of the following parameters are specified: `q`, `link_to_stories`, `link_from_stories_id`.  The `stories_id` and `media_id` parameters can be specified more than once to include stories from more than `stories_id` / `media_id`.

The `sort` parameter will determine the order in which the stories are returned.  The `twitter` sort parameter
will return randomly ordered results unless the topic is a twitter topic.

For a detailed description of the format of the query specified in `q` parameter, see the entry for [stories_public/list](api_2_0_spec.md) in the main API spec.

Standard parameters accepted: snapshots_id, foci_id, timespans_id, limit, link_id.

### Output Description

| Field                | Description                              |
| -------------------- | ---------------------------------------- |
| stories_id           | story id                                 |
| media_id             | media source id                          |
| media_name           | media source name                        |
| url                  | story URL                                |
| title                | story title                              |
| guid                 | story globally unique identifier         |
| language             | two letter code for story language       |
| publish_date         | publication date of the story, or 'undateable' if the story is not dateable |
| date_is_reliable     | boolean indicating whether the date_guess_method is nearly 100% reliable |
| collect_date         | date the story was collected             |
| inlink_count         | count of hyperlinks from stories in other media in this timespan |
| outlink_count        | count of hyperlinks to stories in other media in this timespan |
| facebook_share_count | number of facebook shares for this story's URL |
| foci            | list of foci to which this story belongs |
### Example

Fetch all stories in topic id 1344:

`https://api.mediacloud.org/api/v2/topics/1344/stories/list`

Response:

```json
{
    "stories":
    [
        {
            "stories_id": 168326235,
            "media_id": 18047,
            "collect_date": "2013-10-26 09:25:39",
            "publish_date": "2012-10-24 16:09:26",
            "date_guess_method": "guess_by_og_article_published_time",
            "inlink_count": 531,
            "language": "en",
            "title": "Donald J. Trump (realDonaldTrump) on Twitter",
            "url": "https://twitter.com/realDonaldTrump",
            "outlink_count": 0,
            "guid": "https://twitter.com/realDonaldTrump",
            "foci":
            [
                {
                    "foci_id": 123,
                    "name": "Trump",
                    "focal_set_name": "Candidates"
                }
            ]
        }
    ],
    "link_ids":
    {
        "current": 123456,
        "previous": 456789,
        "next": 789123
    }
}
```

## `topics/<topics_id>/stories/links`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/stories/links`

Return all links between individual stories across media within the given topic.

### Query Parameters

Standard parameters accepted : snapshots_id, foci_id, timespans_id, limit.

### Output Description

| Field | Description                |
| ----- | -------------------------- |
| source_stories_id | id of the story hosting the link |
| ref_stories_id | id of the story that is the target of the link|

### Example

Return links for topic 1404:

`https://api.mediacloud.org/api/v2/topics/1404/stories/links?limit=3`

Response:

```json
{
  "link_ids": {
    "current": 93724,
    "next": 93725
  },
  "links": [
    {
      "ref_stories_id": 7968288,
      "source_stories_id": 9387091
    },
    {
      "ref_stories_id": 8847769,
      "source_stories_id": 9387091
    },
    {
      "ref_stories_id": 169996079,
      "source_stories_id": 9387091
    }
  ]
}
```

## `topics/<topics_id>/stories/facebook`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/stories/facebook`

Return the current facebook counts for all stories in the topic.  Note that this call returns the current
facebook count data, which may change over time, rather than the snapshotted, static data returned by the
stories/list call.

### Query Parameters

Standard parameters accepted : snapshots_id, foci_id, timespans_id, limit.

### Output Description

| Field | Description                |
| ----- | -------------------------- |
| stories_id | story id |
| facebook_share_count | share count from facebook |
| facebook_comment_count | comment count from facebook |
| facebook_api_collect_date | data on which count data was collected from facebook |

### Example

Return the facebook counts for 3 stories in the given topic.

`https://api.mediacloud.org/api/v2/topics/1404/stories/facebook?limit=3`

Response:

```json
{
   "counts" : [
      {
         "facebook_api_collect_date" : "2016-11-25 04:45:35.636022",
         "facebook_comment_count" : 0,
         "facebook" : 0,
         "stories_id" : 737
      },
      {
         "facebook_api_collect_date" : "2016-11-13 11:35:35.657778",
         "facebook_comment_count" : 0,
         "facebook" : 0,
         "stories_id" : 2884
      },
      {
         "facebook_api_collect_date" : "2016-11-13 11:35:35.783757",
         "facebook_comment_count" : 0,
         "facebook" : 0,
         "stories_id" : 3994
      }
   ],
   "link_ids" : {
      "current" : 21797,
      "next" : 21798
   }
}
```

## `topics/<topics_id>/stories/count`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/stories/count`

Return the number of stories that match the query.

### Query Parameters

| Parameter | Default | Notes                               |
| --------- | ------- | ----------------------------------- |
| q         | null    | count stories that match this query |

For a detailed description of the format of the query specified in `q` parameter, see the entry for [stories_public/list](https://github.com/berkmancenter/mediacloud/blob/release/doc/api_2_0_spec/api_2_0_spec.md#apiv2stories_publiclist) in the main API spec.

Standard parameters accepted : snapshots_id, foci_id, timespans_id, limit.

### Output Description

| Field | Description                |
| ----- | -------------------------- |
| count | number of matching stories |

### Example

Return the number of stories that mention 'immigration' in the 'US Election' topic:

`https://api.mediacloud.org/api/v2/topics/<topics_id>/stories/count?q=immigration`

Response:

```json
{ "count": 123 }
```


# Sentences

## `topics/<topics_id>/sentences/count`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/sentences/count`

Return the numer of sentences that match the query, optionally split by date.

This call behaves exactly like the main API sentences/count call, except:

- This call only searches within the given snapshot
- This call accepts the standard topics parameters: snapshots_id, foci_id, timespans_id

For details about this end point, including parameters, output, and examples, see the [main API](https://github.com/berkmancenter/mediacloud/blob/release/doc/api_2_0_spec/api_2_0_spec.md#apiv2sentencescount).

# Media

## `topics/<topics_id>/media/list`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/media/list`

The media list call returns the list of media in the topic.

### Query Parameters

| Parameter | Default | Notes                                    |
| --------- | ------- | ---------------------------------------- |
| media_id  | null    | return only the specified media          |
| sort      | inlink  | possible values: `inlink`, `facebook`, `twitter` |
| name      | null    | search for media with the given name     |
| limit     | 20      | return the given number of media         |
| link_id   | null    | return media using the paging link       |

If the `name` parameter is specified, the call returns only media sources that match a case insensitive search specified value. If the specified value is less than 3 characters long, the call returns an empty list.

The `sort` parameter will determine the order in which the stories are returned.  The `twitter` sort parameter
will return randomly ordered results unless the topic is a twitter topic.

Standard parameters accepted: snapshots_id, foci_id, timespans_id, limit, link_id.

### Output Description

| Field                | Description                              |
| -------------------- | ---------------------------------------- |
| media_id             | medium id                                |
| name                 | human readable label for medium          |
| url                  | medium URL                               |
| story_count          | number of stories in medium              |
| inlink_count         | sum of the inlink_count for each story in the medium |
| outlink_count        | sum of the outlink_count for each story in the medium |
| facebook_share_count | sum of the facebook for each story in the medium |
| focus_ids            | list of ids of foci to which this medium belongs |
| media_source_tags    | list of associated tags |

### Example

Return all stories in the medium that match 'twitt':

`https://api.mediacloud.org/api/v2/topics/<topics_id>/media/list?name=twitt`

Response:

```json
{
    "media":
    [
        {
            "media_id": 18346,
            "story_count": 3475,
            "name": "Twitter",
            "inlink_count": 8454,
            "url": "http://twitter.com",
            "outlink_count": 72,
            "facebooki_share_count": 123,
            "media_source_tags":
                {
                      "description": "Published in United States",
                      "label": "United States",
                      "media_id": 18364,
                      "show_on_media": true,
                      "show_on_stories": null,
                      "tag": "pub_USA",
                      "tag_set": "pub_country",
                      "tag_sets_id": 1935,
                      "tagged_date": null,
                      "tags_id": 9353663
                },
        }
    ],
    "link_ids":
    {
        "current": 123456,
        "previous": 456789,
        "next": 789123
    }
}
```
## `topics/<topics_id>/media/map`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/media/map`

The media list call returns a gexf formatted network map of the media in the topic / timespan.

### Query Parameters

| Parameter | Default | Notes                                    |
| --------- | ------- | ---------------------------------------- |
| color_field  | media_type    | node coloring; possible values: `partisan_code`, `media_type`          |
| num_media      | 500  | number of media to map, sorted by media inlinks |
| include_weights | false | include weights on edges (default is to use a weight of 1 for every edge) |
| num_links_per_medium | null | if set, only inclue the top num_links_per_media out links from each medium, sorted by medium_link_counts.link_count and then inlink_count of the target medium |


Standard parameters accepted: snapshots_id, foci_id, timespans_id.

### Output Description

Output is a gexf formatted file, as described here:

https://gephi.org/gexf/format/

### Example

Return the network map for topic id 12:

`https://api.mediacloud.org/api/v2/topics/12/media/map`


# Word Counts

## `topics/<topics_id>/wc/list`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/wc/list`

Returns sampled counts of the most prevalent words in a topic, optionally restricted to sentences that match a given query.

This call behaves exactly like the main API wc/list call, except:

* This call only searches within the given snapshot
* This call accepts the standard topics parameters: snapshots_id, foci_id, timespans_id

For details about this end point, including parameters, output, and examples, see the [main API](https://github.com/berkmancenter/mediacloud/blob/release/doc/api_2_0_spec/api_2_0_spec.md#apiv2wclist).


# Foci

A *focus* is a set of stories identified through some *focal technique*.  *focal sets* are sets of *foci* that share a *focal technique* and are also usually some substantive theme determined by the user.  For example, a 'U.S. 2016 Election' topic might include a 'Candidates' *focal set* that includes 'trump' and 'clinton' foci, each of which uses a 'Boolean Query' *focal techniqueology* to identify stories relevant to each candidate with a separate boolean query for each.

A specific *focus* exists within a specific *snapshot*.  A single topic might have many 'clinton' *foci*, one for each *snapshot*.  Each *topic* has a number of *focus definion*, each of which tells the system which *foci* to create each time a new *snapshot* is created.  *foci* for new *focus definitions* will be only be created for *snapshots* created after the creation of the *focus definition*.

The relationship of these objects is shown below:

* topic
    * snapshot
        * focus
            * timespan


## Focal Techniques

Details about each focal technique are below.  Among other properties, each focal technique may or not be exclusive.  Exclusive focal techniques generate *focal sets* in which each story belongs to at most one *focus*.

### Focal Technique: Boolean Query

The Boolean Query focal technique associates a focus with a story by matching that story with a Solr boolean query.  *focal sets* generated by the Boolean Query method are not exclusive.

### Focal Technique: Similar Stories

The Similar Stories focal technique associates a focus with a story by matching that story with "similar stories" model. *focal sets* generated by the Similar Stories method are not exclusive.


## `topics/<topics_id>/focal_set_definitions/create` (POST)

`https://api.mediacloud.org/api/topics/<topics_id>/focal_set_definitions/create`

Create and return a new *focal set definiition*  within the given *topic*.

### Query Parameters

(no parameters)

### Input Description

| Field           | Description                              |
| --------------- | ---------------------------------------- |
| name            | short human readable label for focal set definition |
| description     | human readable description of focal set definition |
| focal_technique | focal technique to be used for all focus definitions in this definition |

### Example

Create a 'Candidates' focal set definition in the 'U.S. 2016 Election' topic:

`https://api.mediacloud.org/api/v2/topics/1344/focal_set_definitions/create`

Input:

```json
{
    "name": "Candidates",
    "description": "Stories relevant to each candidate.",
    "focal_techniques": "Boolean Query"
}
```
Response:

```json
{
    "focal_set_definitions":
    [
        {
            "focal_set_definitions_id": 789,
            "topics_id": 456,
            "name": "Candidates",
            "description": "Stories relevant to each candidate.",
            "focal_technique": "Boolean Query",
            "is_exclusive": 0
        }
    ]
}
```

## `topics/<topics_id>/focal_set_definitions/<focal_set_definitions_id>/update` (PUT)

`https://api.mediacloud.org/api/v2/topics/<topics_id>/focal_set_definitions/<focal_set_definitions_id>/update/`

Update the given focal set definition.

### Query Parameters

(no parameters)

### Input Parameters

See *focal_set_definitions/create* for a list of fields.  Only fields that are included in the input are modified.

### Example

Update the name and description of the 'Candidates'  focal set"definition":

`https://api.mediacloud.org/api/v2/topics/1344/focal_set_definitions/789/update`

Input:

```json
{
    "name": "Major Party Candidates",
    "description": "Stories relevant to each major party candidate."
}
```

Response:

```json
{
    "focal_set_definitions":
    [
        {
            "focal_set_definitions_id": 789,
            "topics_id": 456,
            "name": "Major Party Candidates",
            "description": "Stories relevant to each major party candidate.",
            "focal_technique": "Boolean Query",
            "is_exclusive": 0
        }
    ]
}
```

## `topics/<topics_id>/focal_set_definitions/<focal_set_definitions_id>/delete` (PUT)

`https://api.mediacloud.org/api/v2/topics/<topics_id>/focal_set_definitions/<focal_set_definitions_id>/delete`

Delete a focal set definition.

### Query Parameters

(no parameters)

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the focal set defintion was deleted. |

### Example

Delete focal_set_definitions_id 123:

`https://api.mediacloud.org/api/v2/topics/<topics_id>/focal_set_definitions/123/delete`

Response:

```json
{ "success": 1 }
```

## `topics/<topics_id>/focal_set_definitions/list`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/focal_set_definitions/list`

Return a list of all focal set definitions belonging to the given topic.

### Query Parameters

(no parameters)

### Output Description

| Field                    | Description                              |
| ------------------------ | ---------------------------------------- |
| focal_set_definitions_id | focal set defintion id                   |
| name                     | short human readable label for the focal set definition |
| description              | human readable description of the focal set definition |
| focal_technique          | focal technique used for foci in this set |
| is_exclusive             | boolean that indicates whether a given story can only belong to one focus, based on the focal technique |
| focus_definitions        | list of focus definitions belonging to this focal set definition |

### Example

List all focal set definitions associated with the 'U.S. 2016 Elections'"topic":

`https://api.mediacloud.org/api/v2/topics/1344/focal_set_definitions/list`

Response:

```json
{
    "focal_set_definitions":
    [
        {
            "focal_set_definitions_id": 789,
            "topics_id": 456,
            "name": "Major Party Candidates",
            "description": "Stories relevant to each major party candidate.",
            "focal_technique": "Boolean Query",
            "is_exclusive": 0,
            "focus_definitions":
            [
                {
                    "focus_definitions_id": 234,
                    "name": "Clinton",
                    "description": "stories that mention Hillary Clinton",
                    "args": {
                        "query": "clinton and ( hillary or -bill )",
                        // *or*
                        "similarity_models_id": 12345,
                        "negate": false
                    }
                }
            ]

        }
    ]
}
```

## `topics/<topics_id>/focal_sets/list`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/focal_sets/list`

List all *focal sets* belonging to the specified *snapshot* in the given *topic*.

### Query Parameters

Standard parameters accepted: snapshots_id, frames_id, timespans_id.

If no snapshots_id is specified, the latest snapshot will be used.  If foci_id or timespans_id is specified, the snapshot containining that focus or timespan will be used.

### Output Description

| Field           | Description                              |
| --------------- | ---------------------------------------- |
| focal_sets_id   | focal set id                             |
| name            | short human readable label for the focal set |
| description     | human readable description of the focal set |
| focal_technique | focal technique used to generate the foci in the focal set |
| is_exclusive    | boolean that indicates whether a given story can only belong to one focus, based on the focal technique |
| foci            | list of foci belonging to this focal set |

### Example

Get a list of *focal sets* in the latest *snapshot* in the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/focal_sets_list`

Response:

```json
{
    "focal_sets":
    [
        {
            "focal_sets_id": 34567,
            "name": "Candidates",
            "description": "Stories relevant to each candidate.",
            "focal_technique": "Boolean Query",
            "is_exclusive": 0,
            "foci":
            [
                {
                    "foci_id": 234,
                    "name": "Clinton",
                    "description": "stories that mention Hillary Clinton",
                    "focal_technique": "Boolean Query",
                    "args": {
                        "query": "clinton and ( hillary or -bill )",
                        // *or*
                        "similarity_models_id": 12345,
                        "negate": false
                    }
                }
            ]
        }
    ]
}
```


## `topics/<topics_id>/focus_definitions/create` (POST)

`https://api.mediacloud.org/api/topics/<topics_id>/focus_definitions/create`

Create and return a new *focus definition*  within the given *topic* and *focal set definition*.

### Query Parameters

(no parameters)

### Input Description

| Field                    | Description                              | |
| ------------------------ | ---------------------------------------- | |
| name                     | short human readable label for foci generated by this definition | |
| description              | human readable description for foci generated by this definition | |
| args                     | Arguments for the specific focal technique | |
| -                        | query                | Boolean Query: query used to generate foci generated by this definition  |
| -                        | similarity_models_id | Similar Stories: similarity model ID                                     |
| -                        | negate               | Similar Stories: if true, will match stories which don't match the model |
| focus_set_definitions_id | id of parent focus set definition        | |

The input for the *focus definition* depends on the focal technique of the parent *focal set definition*.  The focal technique specific input fields are listed last in the table above and are prefixed with the name of applicable focal technique.

### Example

Create the 'Clinton' *focus definition* within the 'Candidates' *focal set definition* and the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/focus_definitions/create`

Input:

```json
{
    "name": "Clinton",
    "description": "stories that mention Hillary Clinton",
    "args": {
        "query": "clinton",
        // *or*
        "similarity_models_id": 12345,
        "negate": false
    },
    "focal_set_definitions_id": 789
}
```

Response:

```json
{
    "focus_definitions":
    [
        {
            "focus_definitions_id": 234,
            "name": "Clinton",
            "description": "stories that mention Hillary Clinton",
            "focal_technique": "Boolean Query",
            "args": {
                "query": "clinton",
                // *or*
                "similarity_models_id": 12345,
                "negate": false
            }
        }
    ]
}
```


## `topics/<topics_id>/focus_definitions/<focus_definitions_id>/update` (PUT)

`https://api.mediacloud.org/api/v2/topics/<topics_id>/focus_definitions/<focus_definitions_id>/update`

Update the given focus definition.

### Query Parameters

(no parameters)

### Input Description

See *focus_definitions/create* for a list of fields.  Only fields that are included in the input are modified.

### Example

Update the query for the 'Clinton' focus definition:

`https://api.mediacloud.org/api/v2/topics/1344/focus_definitions/234/update`

Input:

```json
{
    "args": {
        "query": "clinton and ( hillary or -bill )",
        // *or*
        "similarity_models_id": 12345,
        "negate": false
    }
}
```

Response:

```json
{
    "focus_definitions":
    [
        {
            "focus_definitions_id": 234,
            "name": "Clinton",
            "description": "stories that mention Hillary Clinton",
            "args": {
                "query": "clinton and ( hillary or -bill )",
                // *or*
                "similarity_models_id": 12345,
                "negate": false
            }
        }
    ]
}
```

## `topics/<topics_id>/focus_definitions/<focus_definitions_id>/delete` (PUT)

`https://api.mediacloud.org/api/v2/topics/<topics_id>/focus_definitions/<focus_definitions_id>/delete`

Delete a focus definition.

### Query Parameters

(no parameters)

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the focus definition was deleted. |

### Example

Delete focus_definitions_id 123:

`https://api.mediacloud.org/api/v2/topics/<topics_id>/focus_definitions/123/delete`

Response:

```json
{ "success": 1 }
```

## `topics/<topics_id>/focus_definitions/list`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/focus_definitions/<focal_set_definitions_id>/list`

List all *focus definitions* belonging to the given *focal set definition*.

### Query Parameters

| Parameter               | Default | Notes                                    |
| ----------------------- | ------- | ---------------------------------------- |
| focal_set_defintions_id | none    | id of parent focal set definition - required |

### Output Description

| Field                | Description                              | |
| -------------------- | ---------------------------------------- | |
| focus_definitions_id | focus definition id                      | |
| name                 | short human readable label for foci generated by this definition | |
| description          | human readable description for foci generated by this definition | |
| args                 | Focal technique-dependent arguments      | |
| -                    | query                | Boolean Query: query used to generate foci generated by this definition  |
| -                    | similarity_models_id | Similar Stories: similarity model ID                                     |
| -                    | negate               | Similar Stories: if true, will match stories which don't match the model |

The output for *focus definition* depends on the focal technique of the parent *focal set definition*.  The framing
method specific fields are listed last in the table above and are prefixed with the name of applicable focal technique.

### Example

List all *focus definitions* belonging to the 'Candidates' *focal set definition* of the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/focus_definitions/234/list`

Response:

```json
{
    "focus_definitions":
    [
        {
            "focus_definitions_id": 234,
            "name": "Clinton",
            "description": "stories that mention Hillary Clinton",
            "args": {
                "query": "clinton and ( hillary or -bill )",
                // *or*
                "similarity_models_id": 12345,
                "negate": false
            }
        }
    ]
}
```

## `topics/<topics_id>/foci/list`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/foci/list`

Return a list of the *foci* belonging to the given *focal set*.

### Query Parameters

| Parameter     | Default | Notes                                 |
| ------------- | ------- | ------------------------------------- |
| focal_sets_id | none    | id of the parent focal set - required |

### Ouput Description

| Field       | Description                              | |
| ----------- | ---------------------------------------- | |
| foci_id     | focus id                                 | |
| name        | short human readable label for the focus | |
| description | human readable description of the focus  | |
| args        | Focal technique-dependend arguments      | |
| -           | query                | Boolean Query: query used to generate the focus                          |
| -           | similarity_models_id | Similar Stories: similarity model ID                                     |
| -           | negate               | Similar Stories: if true, will match stories which don't match the model |

The output for *focus* depends on the focal technique of the parent *focus definition*.  The focal technique specific fields are listed last in the table above and are prefixed with the name of applicable focal technique.

### Example

Get a list of *foci* wihin the 'Candiates' *focal set* of the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/foci/list?focal_sets_id=234`

Response:

```json
{
    "foci":
    [
        {
            "foci_id": 234,
            "name": "Clinton",
            "description": "stories that mention Hillary Clinton",
            "args": {
                "query": "clinton and ( hillary or -bill )",
                // *or*
                "similarity_models_id": 12345,
                "negate": false
            }
        }
    ]
}
```


## Story Similarity Models

### `topics/<topics_id>/similarity_models/preview` (POST)

| URL                                                   | Function                                                                                                    |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `api/v2/topics/<topics_id>/similarity_models/preview` | Generate a sample similarity model using a list of stories and evaluate it against another list of stories. |

#### Required role

`admin-read`.

#### Input Description

| Parameter            | Notes                                                        | -                                                      |
| -------------------- | ------------------------------------------------------------ | ------------------------------------------------------ |
| `training_stories`   | *(list of dictionaries)* Stories to train a sample similarity model with. | -                                                      |
| -                    | `stories_id`                                                 | *(integer)* Story's ID.                                |
| -                    | `judgement`                                                  | *(boolean)* Whether or not a story belongs in a focus. |
| `evaluation_stories` | *(list of integer story IDs)* Stories to evaluate a sample model against. | -                                                      |

#### Output Description

##### Sample model was generated and evaluation stories were run against it

```json
{
    "success": 1,
    "evaluated_stories": {
        "1": true,
        "2": true,
        "3": false
    }
}
```

##### An error has occurred

```json
{
    "error": "Unable to generate similarity model: ..."
}
```

#### Example

URL: <https://api.mediacloud.org/api/v2/topics/1344/similarity_models/preview>

Input:

```json
{
    "training_stories": [
        {
            "stories_id": 1,
            "judgement": true
        },
        {
            "stories_id": 2,
            "judgement": true
        },
        {
            "stories_id": 3,
            "judgement": false
        }
    ],
    "evaluation_stories": [
        4,
        5,
        6
    ]
}
```

Output:

```json
{
    "success": 1,
    "evaluated_stories": {
        "4": true,
        "5": true,
        "6": false
    }
}
```


### `topics/<topics_id>/similarity_models/create` (POST)

| URL                                                  | Function                                                       |
| ---------------------------------------------------- | -------------------------------------------------------------- |
| `api/v2/topics/<topics_id>/similarity_models/create` | Generate and save a similarity model using a list of stories.  |

#### Required role

`admin`.

#### Input Description

| Parameter            | Notes                                                              | |
| -------------------- | ------------------------------------------------------------------ | |
| `name`               | *(string)* Model name                                              | |
| `description`        | *(string)* Model description                                       | |
| `training_stories`   | *(list of dictionaries)* Stories to train a similarity model with. | |
| -                    | `stories_id`                                                       | *(integer)* Story's ID.                                |
| -                    | `judgement`                                                        | *(boolean)* Whether or not a story belongs in a focus. |

#### Output Description

##### Model was generated and stored

```json
{
    "success": 1,
    "similarity_model": {
        "similarity_models_id": "(integer) ID of the created model to be associated with focal technique",
        "name": "(string) Model name",
        "description": "(string) Model description",
        "created_date": "(ISO 8601 date) of when the model was created.",
        "training_stories": [
            {
                "stories_id": "(integer) Story ID that was used for training.",
                "judgement": "(boolean) Judgement that was used for training."
            }
        ]
    }
}
```

##### An error has occurred

```json
{
    "error": "Unable to generate similarity model: ..."
}
```

#### Example

URL: <https://api.mediacloud.org/api/v2/topics/1344/similarity_models/create>

Input:

```json
{
    "name": "Test model",
    "description": "This is a test model.",
    "training_stories": [
        {
            "stories_id": 1,
            "judgement": true
        },
        {
            "stories_id": 2,
            "judgement": true
        },
        {
            "stories_id": 3,
            "judgement": false
        }
    ]
}
```

Output:

```json
{
    "success": 1,
    "similarity_model": {
        "similarity_models_id": 12345,
        "name": "Test model",
        "description": "This is a test model.",
        "created_date": "2017-03-24T03:23:47+00:00",
        "training_stories": [
            {
                "stories_id": 1,
                "judgement": true
            },
            {
                "stories_id": 2,
                "judgement": true
            },
            {
                "stories_id": 3,
                "judgement": false
            }
        ]
    }
}
```


### `topics/<topics_id>/similarity_models/list` (GET)

| URL                                                | Function                |
| -------------------------------------------------- | ----------------------- |
| `api/v2/topics/<topics_id>/similarity_models/list` | List similarity models. |

#### Required role

`admin-readonly`.

#### Output Description

##### Model was generated and stored

```json
{
    "success": 1,
    "similarity_models_id": 12345
}
```

##### An error has occurred

```json
{
    "error": "Unable to list similarity models: ..."
}
```

#### Example

URL: <https://api.mediacloud.org/api/v2/topics/1344/similarity_models/list>

Output:

```json
[
    {
        "similarity_models_id": 12345,
        "name": "Test model",
        "description": "This is a test model.",
        "created_date": "2017-03-24T03:23:47+00:00",
        "training_stories": [
            {
                "stories_id": 1,
                "judgement": true
            },
            {
                "stories_id": 2,
                "judgement": true
            },
            {
                "stories_id": 3,
                "judgement": false
            }
        ]
    }
]
```


# Snapshots

Each *snapshot* contains a static copy of all data within a topic at the time the *snapshot* was made.  All data viewable by the Topics API must be viewed through a *snapshot*.

## `topics/<topics_id>/snapshots/generate` (POST)

`https://api.mediacloud.org/api/v2/topics/<topics_id>/snapshots/generate`

Generate a new *snapshot* for the given topic.  Note that `topics/spider` will generate a snapshot as part of its
spidering process, so this end point only needs to be called to generate an additional snapshot of a topic
without also spidering (for instance after editing the foci definitions).

This is an asynchronous call.  The *snapshot* process will run in the background, and the new *snapshot* will only become visible to the API once the generation is complete.

### Query Parameters

(no parameters)

### Input Description

| Field | Description                              |
| ----- | ---------------------------------------- |
| note  | short text note about the snapshot; optional |

### Output Description

This command will return a job_state object as described in the `snapshots/generate_status` call below.

### Example

Start a new *snapshot* generation job for the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/snapshots/generate`

Response:

```json
{
    "job_state":
        {
            "topics_id": 1404,
            "job_states_id": 1,
            "last_updated": "2017-01-26 14:27:04.781095",
            "message": null,
            "state": "queued"
        }
}
```

## `topics/<topics_id>/snapshots/generate_status`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/snapshots/generate_status`

Return a list of snapshots job_states for the given snapshot;

### Query Parameters

(no parameters)

### Input Description

| Field | Description                              |
| ----- | ---------------------------------------- |
| note  | short text note about the snapshot; optional |

### Output Description

| Field    | Description                              |
| -------- | ---------------------------------------- |
| state | one of queued, running, completed, or error |
| message | more detailed message about the job state |
| last_updated | date of last state change |
| topics_id | id the topic being snapshotted |

### Example

List snapshot jobs for the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/snapshots/generate_status`

Response:

```json
{
    "job_states": [
        {
            "topics_id": 1404,
            "job_states_id": 1,
            "last_updated": "2017-01-27 14:27:04.781095",
            "message": null,
            "state": "completed"
        }
    ]
}
```

## `topics/<topics_id>/snapshots/list`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/snapshots/list`

Return a list of all completed *snapshots* in the given *topic*.

### Query Paramaters

(no parameters)

### Output Description

| Field           | Description                            |
| --------------- | -------------------------------------- |
| snapshots_id    | snapshot id                            |
| snapshot_date   | date on which the snapshot was created |
| note            | short text note about the snapshot     |
| state           | state of the snapshotting process      |
| message         | more detailed message about the state of the snapshotting process |
| searchable      | boolean indicating whether timespans are searchable yet |
| word2vec_models | List of word2vec models generated for the snapshot |

The state indicates the state of the current snapshot process, including but not limited to 'completed' for a snapshot
whose process has successfully completed and 'error' for a snapshot that failed for some reason.

Each timespan in a snapshot is queued for text indexing when the snapshot is generated.  This process may take a
few minutes up to a few hours.  The 'searchable' field is set to true once that indexing process is complete.

### Example

Return a list of *snapshots* in the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/snapshots/list`

Response:

```json
{
    "snapshots":
    [
        {
            "snapshots_id": 6789,
            "snapshot_date": "2016-09-29 18:14:47.481252",
            "note": "final snapshot for paper analysis",
            "state": "completed",
            "word2vec_models": [
               {
                  "models_id": 1,
                  "creation_date": "2018-01-31 20:59:57.559360"
               }
            ]
        }
    ]
}
```


## `topics/<topics_id>/snapshots/<snapshots_id>/word2vec_model/<models_id>` (GET)

| URL                                                                      | Function                             |
| ------------------------------------------------------------------------ | ------------------------------------ |
| `topics/<topics_id>/snapshots/<snapshots_id>/word2vec_model/<models_id>` | Download snapshots's word2vec model. |

### Required role

`topics_read`.

### Output Description

#### Model was fetched

Raw, [Pickle](https://docs.python.org/3/library/pickle.html)-serialized word2vec data is returned as `application/octet-stream`, to be later loaded with:

```python
model = KeyedVectors.load(path_to_model_data)
```

#### Failed to fetch the model

```json
{
    "error": "Reason why the model can't be fetched."
}
```

### Example

URL: <https://api.mediacloud.org/api/v2/topics/6/snapshots/1/word2vec_model/1>

Output: `application/octet-stream` model data of topic with `topics_id=6`, snapshot with `snapshots_id=1`, word2vec model with `models_id=1`.


# Timespans

Each *timespan* is a view of the *topic* that presents the topic as if it consists only of *stories* within the date range of the given *timespan*.

A *story* is included within a *timespan* if the publish_date of the story is within the *timespan* date range or if the *story* is linked to by a *story* that whose publish_date is within date range of the *timespan*.

## `topics/<topics_id>/timespans/list`

`https://api.mediacloud.org/api/v2/topics/<topics_id>/timespans/list`

Return a list of timespans in the current snapshot.

### Query Parameters

Standard parameters accepted: snapshots_id, foci_id, timespans_id.

### Output Description

| Field             | Description                              |
| ----------------- | ---------------------------------------- |
| timespans_id      | timespan id                              |
| period            | type of period covered by timespan; possible values: overall, weekly, monthly, custom |
| start_date        | start of timespan date range             |
| end_date          | end of timespan date range               |
| story_count       | number of stories in timespan            |
| story_link_count  | number of cross media story links in timespan |
| medium_count      | number of distinct media associated with stories in timespan |
| medium_link_count | number of cros media media links in timespan |
| model_r2_mean     | timespan modeling r2 mean                |
| model_r2_stddev   | timespan modeling r2 standard deviation  |
| model_num_media   | number of media include in modeled top media list |
| foci_id           | id of focus to which the timespan belongs |
| snapshots_id      | id of snapshot to which the timespan belongs |

Every *topic* generates the following timespans for every *snapshot*:

* overall - an timespan that includes every story in the topic
* custom all - a custom period timespan that includes all stories within the date range of the topic
* weekly - a weekly timespan for each calendar week in the date range of the topic
* monthly - a monthly timespan for each calendar month in the date range of the topic

Media Cloud needs to guess the date of many of the stories discovered while topic spidering.  We have validated the date guessing to be about 87% accurate for all methods other than the finding a URL in the story URL.  The possiblity of significant date errors make it possible for the Topic Mapper system to wrongly assign stories to a given timespan and to also miscount links within a given timespan (due to stories getting misdated into or out of a given timespan).  To mitigate the risk of drawing the wrong research conclusions from a given timespan, we model what the timespan might look like if dates were wrong with the frequency that our validation tell us that they are wrong within a given timespan.  We then generate a pearson's correlation between the ranks of the top media for the given timespan in our actual data and in each of ten runs of the modeled data.  The model_* fields provide the mean and standard deviations of the square of those correlations.

### Example

Return all *timespans* associated with the latest *snapshot* of the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/timespans/list`

Response:

```json
{
    "timespans":
    [
        {
            "timespans_id": 6789,
            "period": "overall",
            "start_date": "2016-01-01",
            "end_date": "2016-12-01",
            "story_count": 10283,
            "story_link_count": 543,
            "medium_count": 2345,
            "medium_link_count": 1543,
            "model_r2_mean": 0.94,
            "model_r2_stddev": 0.04,
            "model_num_media": 143,
            "foci_id": null,
            "snapshots_id": 456
        }
    ]
}
```
