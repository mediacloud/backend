<!-- MDTOC maxdepth:6 firsth1:1 numbering:0 flatten:0 bullets:1 updateOnSave:1 -->

- [Overview](#overview)   
   - [Media Cloud Crawler and Core Data Structures](#media-cloud-crawler-and-core-data-structures)   
   - [Topic Data Structures](#topic-data-structures)   
   - [API URLs](#api-urls)   
   - [Snapshots, Timespans, and Frames](#snapshots-timespans-and-frames)   
   - [Paging](#paging)   
   - [Examples](#examples)   
- [Topics](#topics)   
   - [topics/create (POST)](#topicscreate-post)   
      - [Query Parameters](#query-parameters)   
      - [Input Description](#input-description)   
      - [Example](#example)   
   - [topics/~topics_id~/edit (PUT)](#topicstopics_idedit-put)   
      - [Query Parameters](#query-parameters-1)   
      - [Input Description](#input-description-1)   
      - [Example](#example-1)   
   - [topics/~topics_id~/spider](#topicstopics_idspider)   
      - [Query Parameters](#query-parameters-2)   
      - [Output Description](#output-description)   
      - [Example](#example-2)   
   - [topics/~topics_id~/iterations/list](#topicstopics_iditerationslist)   
      - [Query Parameters](#query-parameters-3)   
      - [Output Description](#output-description-1)   
      - [Example](#example-3)   
   - [topics/list](#topicslist)   
      - [Query Parameters](#query-parameters-4)   
      - [Output Description](#output-description-2)   
      - [Example](#example-4)   
- [Stories](#stories)   
   - [stories/list](#storieslist)   
      - [Query Parameters](#query-parameters-5)   
      - [Output Description](#output-description-3)   
      - [Example](#example-5)   
   - [stories/count](#storiescount)   
      - [Query Parameters](#query-parameters-6)   
      - [Output Description](#output-description-4)   
      - [Example](#example-6)   
   - [stories/~stories_id~/edit (PUT)](#storiesstories_idedit-put)   
      - [Query Parameters](#query-parameters-7)   
      - [Input Description](#input-description-2)   
      - [Output Description](#output-description-5)   
      - [Example](#example-7)   
   - [stories/~stories_id~/remove (PUT)](#storiesstories_idremove-put)   
      - [Query Parameters](#query-parameters-8)   
      - [Output Description](#output-description-6)   
      - [Example](#example-8)   
   - [stories/merge (PUT)](#storiesmerge-put)   
      - [Query Parameters](#query-parameters-9)   
      - [Input Description](#input-description-3)   
      - [Output Description](#output-description-7)   
      - [Example](#example-9)   
- [Sentences](#sentences)   
   - [sentences/count](#sentencescount)   
- [Media](#media)   
   - [media/list](#medialist)   
      - [Query Parameters](#query-parameters-10)   
      - [Output Description](#output-description-8)   
      - [Example](#example-10)   
   - [media/~media_id~/edit (PUT)](#mediamedia_idedit-put)   
      - [Query Parameters](#query-parameters-11)   
      - [Input Description](#input-description-4)   
      - [Example](#example-11)   
   - [media/~media_id~/remove (PUT)](#mediamedia_idremove-put)   
      - [Query Parameters](#query-parameters-12)   
      - [Output Description](#output-description-9)   
      - [Example](#example-12)   
   - [media/merge (PUT)](#mediamerge-put)   
      - [Query Parameters](#query-parameters-13)   
      - [Input Description](#input-description-5)   
      - [Output Description](#output-description-10)   
      - [Example](#example-13)   
- [Word Counts](#word-counts)   
   - [wc/list](#wclist)   
- [Frames](#frames)   
   - [Framing Methods](#framing-methods)   
      - [Framing Method: Boolean Query](#framing-method-boolean-query)   
   - [frame_set_definitions/create (POST)](#frame_set_definitionscreate-post)   
      - [Query Parameters](#query-parameters-14)   
      - [Input Description](#input-description-6)   
      - [Example](#example-14)   
   - [frame_set_definitions/~frame_set_definitions_id~/update (PUT)](#frame_set_definitionsframe_set_definitions_idupdate-put)   
      - [Query Parameters](#query-parameters-15)   
      - [Input Parameters](#input-parameters)   
      - [Example](#example-15)   
   - [frame_set_definitions/~frame_set_definitions_id~/delete (PUT)](#frame_set_definitionsframe_set_definitions_iddelete-put)   
      - [Query Parameters](#query-parameters-16)   
      - [Output Description](#output-description-11)   
      - [Example](#example-16)   
   - [frame_set_definitions/list](#frame_set_definitionslist)   
      - [Query Parameters](#query-parameters-17)   
      - [Output Description](#output-description-12)   
      - [Example](#example-17)   
   - [frame_sets/list](#frame_setslist)   
      - [Query Parameters](#query-parameters-18)   
      - [Output Description](#output-description-13)   
      - [Example](#example-18)   
   - [frame_definitions/~frame_set_definitions_id~/create (POST)](#frame_definitionsframe_set_definitions_idcreate-post)   
      - [Query Parameters](#query-parameters-19)   
      - [Input Description](#input-description-7)   
      - [Example](#example-19)   
   - [frame_definitions/~frame_definitions_id~/update (PUT)](#frame_definitionsframe_definitions_idupdate-put)   
      - [Query Parameters](#query-parameters-20)   
      - [Input Description](#input-description-8)   
      - [Example](#example-20)   
   - [frame_definitions/list](#frame_definitionslist)   
      - [Query Parameters](#query-parameters-21)   
      - [Output Description](#output-description-14)   
      - [Example](#example-21)   
   - [frames/list](#frameslist)   
      - [Query Parameters](#query-parameters-22)   
      - [Ouput Description](#ouput-description)   
      - [Example](#example-22)   
- [Snapshots](#snapshots)   
   - [snapshots/generate (POST)](#snapshotsgenerate-post)   
      - [Query Parameters](#query-parameters-23)   
      - [Input Description](#input-description-9)   
      - [Output Description](#output-description-15)   
      - [Example](#example-23)   
      - [snapshots/list](#snapshotslist)   
      - [Query Paramaters](#query-paramaters)   
      - [Output Description](#output-description-16)   
      - [Example](#example-24)   
   - [snapshots/~snapshots_id~/edit (PUT)](#snapshotssnapshots_idedit-put)   
      - [Query Parameters](#query-parameters-24)   
      - [Input Description](#input-description-10)   
      - [Output Description](#output-description-17)   
      - [Example](#example-25)   
- [Timespans](#timespans)   
   - [timespans/list](#timespanslist)   
      - [Query Parameters](#query-parameters-25)   
      - [Output Description](#output-description-18)   
      - [Example](#example-26)   
   - [timespans/add_dates (PUT)](#timespansadd_dates-put)   
      - [Query Parameters](#query-parameters-26)   
      - [Input Description](#input-description-11)   
      - [Output Description](#output-description-19)   
      - [Example](#example-27)   
   - [timespans/list_dates](#timespanslist_dates)   
      - [Query Parameters](#query-parameters-27)   
      - [Output Description](#output-description-20)   
      - [Example](#example-28)   
- [TODO](#todo)   

<!-- /MDTOC -->

# Overview

This document described the Media Cloud Topics API.  The Topics API is a subset of the larger Media Cloud API.  The Topics API provides access to data about Media Cloud Topics and related data.  For a fuller understanding of Media Cloud data structures and for information about *Authentication*, *Request Limits*, the API *Python Client*, and *Errors*, see the documentation for the main [link: main api] Media Cloud API.

The topics api is currently under development and is available only to Media Cloud team members and select beta testers.  Email us at info@mediacloud.org if you would like to beta test the Topics API.

A *topic* currently may be created only by the Media Cloud team, though we occasionally run topics for external researchers.

## Media Cloud Crawler and Core Data Structures

The core Media Cloud data are stored as *media*, *feeds*, and *stories*.  

A *medium* (or *media source*) is a publisher, which can be a big mainstream media publisher like the New York Times, an
activist site like fightforthefuture.org, or even a site that does not publish regular news-like stories, such as Wikipedia.  

A *feed* is a syndicated feed (RSS, RDF, ATOM) from which Media Cloud pulls stories for a given *media source*.  A given
*media source* may have anywhere from zero *feeds* (in which case we do not regularly crawl the site for new content) up
to hundreds of feeds (for a site like the New York Times to make sure we collect all of its content).

A *story* represents a single published piece of content within a *media source*.  Each *story* has a unique url within
a given *media source*, even though a single *story* might be published under multiple urls.  Media Cloud tries
to deduplicate stories by title.

The Media Cloud crawler regularly downloads every *feed* within its database and parses out all urls from each *feed*.
It downloads every new url it discovers and adds a *story* for that url, as long as the story is not a duplicate for
the given *media source*.  The Media Cloud archive consists primarily of *stories* collected by this crawler.

## Topic Data Structures

A Media Cloud *topic* is a set of stories relevant to some subject.  The topic spider starts by searching for a
set of stories relevant to the story within the Media Cloud archive and then spiders urls from those
stories to find more relevant stories, then iteratively repeats the process 15 times.

After the spidering is complete, a *topic* consists of a set of relevant *stories*, *links* between those stories, the
*media* that published those *stories*, and social media metrics about the *stories* and *media*.  The various topics /
end points provide access to all of this raw data as well as various of various analytical processes applied to this
data.

## API URLs

All urls in the topics api are in the form:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/list`

For example, the following will return all stories in the latest snapshot of topic id 1344.

`https://api.mediacloud.org/api/v2/topics/1344/stories/list`

## Snapshots, Timespans, and Frames

Each *topic* is viewed through one of its *snapshots*.  A *snapshot* is static dump of all data from a topic at
a given point in time.  The data within a *snapshot* will never change, so changes to a *topic* are not visible
until a new *snapshot* is made.
<!-- RB - really? what is someone decides to remove a media source from a snapshot... does that generate a new snapshot automatically? -->
<!-- HR - really!  no data changes in the current snapshot.  a new one has to be created to see any changes.
we can discuss whether there should be automatic triggers for creating a new snapshot or not.  think about the
snapshot as a report that you are delivering to the user, not any kind of live view of the data.  editing media and story metadata will always be an internal option only, though, because those edits are to our core stories and media tables.  but story removal or merges will likewise not be visible until the next snapshot.   -->

Within a *snapshot*, data can be viewed overall, or through some combination of a *frame* and a *timespan*.

A *frame* consists of a subset of stories within a *topic* defined by some user configured *framing method*.  For
example, a 'trump' *frame* within a 'US Election' *topic* would be defined using the 'Boolean Query' *framing method*
as all stories matching the query 'trump'.  Each individual *frame* belongs to exactly one *frame set*.  A *frame set*
provides a way of collecting together *frames* for easy comparison to one another.

A *timespan* displays the *topic* as if it exists only of stories either published within the date range of the
*timespan* or linked to by a story published within the date range of the *timespan*.

*Topics*, *snapshots*, *frames*, and *timespans* are strictly hierarchical.  Every *snapshot* belongs to a single
*topic*.  Every *frame* belongs to a single *snapshot*, and every *timespan* belongs to either a single *frame* or the
null *frame*.  Specifying a *frame* implies the parent *snapshot* of that *frame*.  Specifying a *timespan* implies the
parent *frame* (and by implication the parent *snapshot*), or else the null *frame* within the parent *snapshot*.

* topic
  * snapshot
    * frame
      * timespan

Every url that returns data from a *topic* accepts optional *spanshots_id*, *timespans_id*, and *frames_id* parameters.

If no *snapshots_id* is specified, the call returns data from the latest *snapshot* generated for the *topic*.  If no
*timespans_id* is specified, the call returns data from the overall *timespan* of the given *snapshot* and *frame*.  If
no *frames_id* is specified, the call assumes the null *frame*.  If multiple of these parameters are specified,
they must point to the same *topic* / *snapshot* / *frame* / *timespan* or an error will be returned (for instance, a
call that specifies a *snapshots_id* for a *snapshot* in a *topic* different from the one specified in the url, an error
will be returned).

## Paging

For calls that support paging, each url supports a *limit* parameter and a *link_id* parameter.  For these calls, only
*limit* results will be returned at a time, and a set of *link_ids* will be returned along with the results.  To get the
current set of results again, or the previous or next page of results, call the same end point with only the *key* and
*link_id* parameters. The *link_id* parameter includes state that remembers all of the parameters from the original
call.
<!-- RB - what is the *key* parameter? Is that just a typo? -->
<!-- HR - the key parameter is used for authentication.  authentication is referenced as a link to the main api spec
above.  just mentioning here to make clear that links don't provide unauthenticated access -->

For example, the following is a paged response:

```json
{
    "stories":
    [
        {   
            "stories_id": 168326235,
            "media_id": 18047,
            "bitly_click_count": 182,
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

After receiving that reponse, you can use the following url with no other parameters to fetch the next page of results:

`https://api.mediacloud.org/api/v2/topics/1/stories/list?link_id=789123`

When the system has reached the end of the results, it will return an empty list and a null 'next' *link_id*.

*link_ids* are persistent — they can be safely used to refer to a given result forever (for instance, as an identifier for a link shortener).

## Examples

The section for each end point includes an example call and response for that end point.  For end points that return multiple results, we generally only show a single result (for instance a single story) for the sake of documentation brevity.

# Topics

## topics/create (POST)

`https://api.mediacloud.org/api/v2/topics/create`

Create and return a new *topic*..

### Query Parameters

(no parameters)

### Input Description

The topics/create call accepts as input the following fields described in the Output Description of the topics/list call: name, pattern, solr_query, description, max_iterations, start_date, end_date.

### Example

Create a new topic:

`https://api.mediacloud.org/api/v2/topics/create`

Input:

```json
{
    "name": "immigration 2015",
    "description": "immigration coverage during 2015",
    "pattern": "[[:<:]]immigration",
    "solr_seed_query": "immigration AND (+publish_date:[2016-01-01T00:00:00Z TO 2016-06-15T23:59:59Z]) AND tags_id_media:8875027",
    "max_iterations": 15,
    "start_date": "2015-01-01",
    "end_date": "2015-12-31"
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
	}
  ]
}
```



<!-- RB - are the names unique?  if so, what is the error returned? -->
<!-- HR - names are unique. we have a crappy error reporting system that just basically returns the
error directly from perl, so the error in this case would just be an echo of the unique constraint.  implementing
a well documented set of errors would be very time expensive, but maybe pick a few likely triggered errors like this
to have saner errors for? -->

<!-- TODO - RB - do we need a public flag? or is that something we'll figure out with the permissions stuff separately -->

## topics/~topics_id~/edit (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/edit`

Edit an existing *topic*.

### Query Parameters

(no parameters)

### Input Description

Accepts the same input as the topics/create call.

### Example

Edit the 'immigration 2015' topic.

Input:

```json
{
    "name": "immigration coverage 2015",
    "description": "immigration coverage during 2015",
    "pattern": "[[:<:]]immigration",
    "solr_seed_query": "immigration AND (+publish_date:[2016-01-01T00:00:00Z TO 2016-06-15T23:59:59Z]) AND tags_id_media:8875027",
    "max_iterations": 15,
    "start_date": "2015-01-01",
    "end_date": "2015-12-31"
}
```

Response:

```json
{
  "topics":
  [
    {
      "topics_id": 1390,
      "name": "immigration coverage 2015",
      "description": "immigration coverage during 2015",
      "pattern": "[[:<:]]immigration",
      "solr_seed_query": "immigration AND (+publish_date:[2016-01-01T00:00:00Z TO 2016-06-15T23:59:59Z]) AND tags_id_media:8875027",
      "max_iterations": 15,
      "start_date": "2015-01-01",
      "end_date": "2015-12-31",
      "state": "created but not queued",
	}
  ]
}
```

## topics/~topics_id~/spider

`https://api.mediacloud.org/api/v2/topics/~topics_id~/spider`

Start a topic spidering job.

Topic spidering is asynchronous.  Once the topic has started spidering, you cannot start another spidering job until the current one is complete.

<!-- RB - what does this return if you try to start one when one is already running? -->
<!-- HR - it should just run the, potentially at the same time.  there are valid reasons for
doing this, for instance if the current job is in the middle of a dump but you want to edit the definition a bit
and rerun the spider but still have access to the currently generating dump while the new spider is running.  that sounds
contrived but I actually do it every once in a while -->

### Query Parameters

(no parameters)

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating whether the spidering job was successfully queued. |

### Example

Start a topic spider for the 'U.S. 2016 Election' topic:

`https://api.mediacloud.org/api/v2/topics/1344/spider`

Response:

```json
{ "success": 1 }
```

## topics/~topics_id~/iterations/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/iterations/list`

Return list of spider iterations with a story count for each

### Query Parameters

(no parameters)

### Output Description

| Field       | Description                    |
| ----------- | ------------------------------ |
| iteration   | number of iteration            |
| story_count | number of stories in iteration |

### Example

Get the list of iterations for the 'U.S. 2016 Election' topic:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/iterations/list`

Response:

```json
{
  "iterations":
  [
    {
      "iteration": 0,
      "count": 500,
    },
    {
      "iteration": 1,
      "count": 1000,
    },
    {
      "iteration": 2,
      "count": 300,
    }
  ]
}
```

## topics/list

`https://api.mediacloud.org/api/v2/topics/list`

The topics/list call returns a simple list of topics available in Media Cloud.  The topics/list call is is only call
that does not include a topics_id in the url.

### Query Parameters

Standard parameters accepter: link_id.

### Output Description

| Field               | Description                              |
| ------------------- | ---------------------------------------- |
| topics_id           | topic id                                 |
| name                | human readable label                     |
| pattern             | regular expression derived from solr query |
| solr_seed_query     | solr query used to generate seed stories |
| solr_seed_query_run | boolean indicating whether the solr seed query has been run to seed the topic |
| description         | human readable description               |
| max_iterations      | maximum number of iterations for spidering |
| start_date          | start of date range for topic            |
| end_date            | end of date range for topic              |
| state               | the current status of the spidering process |
| error_message       | last error message generated by the spider, if any |

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
            "error_message": ""
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
<!-- TODO - do we want to add the user that created/requested this to the output? -->

<!-- RB - what about topics/single?  I need that.  it is currently implemented as controversies/single, but I'd like the spider status added to those results -->
<!-- HR -  I really hate having multiple end points that do the same thing.  is it really that much easier to call topics/single/123 rather than topics/list?topics_id=123 ? -->

# Stories

## stories/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/list`

The stories list call returns stories in the topic.

### Query Parameters

| Parameter            | Default | Notes                                    |
| -------------------- | ------- | ---------------------------------------- |
| q                    | null    | if specified, return only stories that match the given solr query |
| sort                 | inlink  | sort field for returned stories; possible values: `inlink`, `social` |
| stories_id           | null    | return only stories matching these stories_ids |
| link_to_stories_id   | null    | return only stories from other media that link to the given stories_ids |
| link_from_stories_id | null    | return only stories from other media that are linked from the given stories_ids |
| media_id             | null    | return only stories belonging to the given media_ids |
| limit                | 20      | return the given number of stories       |
| link_id              | null    | return stories using the paging link     |

The call will return an error if more than one of the following parameters are specified: `q`, `stories_id`, `link_to_stories`, `link_from_stories_id`, `media_id`.

For a detailed description of the format of the query specified in `q` parameter, see the entry for [stories_public/list](api_2_0_spec.md) in the main API spec.

Standard parameters accepted: snapshots_id, frames_id, timespans_id, limit, link_id.

### Output Description

| Field                | Description                              |
| -------------------- | ---------------------------------------- |
| stories_id           | story id                                 |
| media_id             | media source id                          |
| media_name           | media source name                        |
| url                  | story url                                |
| title                | story title                              |
| guid                 | story globally unique identifier         |
| language             | two letter code for story language       |
| publish_date         | publication date of the story, or 'undateable' if the story is not dateable |
| date_is_reliable     | boolean indicating whether the date_guess_method is nearly 100% reliable |
| collect_date         | date the story was collected             |
| date_guess_method    | method used to guess the publish_date    |
| inlink_count         | count of hyperlinks from stories in other media in this timespan |
| outlink_count        | count of hyperlinks to stories in other media in this timespan |
| bitly_click_count    | number of clicks on bitly links that resolve to this story's url |
| facebook_share_count | number of facebook shares for this story's url |
| frame_ids            | list of ids of frames to which this story belongs |
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
            "bitly_click_count": 182,
            "collect_date": "2013-10-26 09:25:39",
            "publish_date": "2012-10-24 16:09:26",
            "date_guess_method": "guess_by_og_article_published_time",
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

## stories/count

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/count`

Return the number of stories that match the query.

### Query Parameters

| Parameter | Default | Notes                               |
| --------- | ------- | ----------------------------------- |
| q         | null    | count stories that match this query |

For a detailed description of the format of the query specified in `q` parameter, see the entry for [stories_public/list](https://github.com/berkmancenter/mediacloud/blob/release/doc/api_2_0_spec/api_2_0_spec.md#apiv2stories_publiclist) in the main API spec.

Standard parameters accepted : snapshots_id, frames_id, timespans_id, limit.

### Output Description

| Field | Description                |
| ----- | -------------------------- |
| count | number of matching stories |

<!-- RB - it'd be awesome if this can include split params, but I understand that might need to wait until new hardware -->
<!-- HR - definitely not possible now -->

### Example

Return the number of stories that mention 'immigration' in the 'US Election' topic:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories_count?q=immigration`

Response:

```json
{ "count": 123 }
```

## stories/~stories_id~/edit (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/~stories_id~/edit`

Edit and return a story.  Editing a story changes that story for all topics.

### Query Parameters

(no parameters)

### Input Description

| Field        | Description                              |
| ------------ | ---------------------------------------- |
| stories_id   | id of story to edit; required            |
| title        | story title                              |
| publish_date | story publication date in this format: 2016-06-30 15:34:45Z or 'undateable' |

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the story was successfully edited. |

### Example

Edit the publish_date of story 123456:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/~stories_id~/edit`

Input:

```json
{
  "publish_date": "2016-05-30 15:34:45"
}
```

Response:

(see stories/list)

## stories/~stories_id~/remove (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/~stories_id~/remove`

Remove the given story from the topic (but do not delete it from Media Cloud).

### Query Parameters

(no parameters)

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the story was removed |

### Example

Remove stories_id 12345 from topics_id 1340:

`https://api.mediacloud.org/api/v2/topics/1340/stories/12345/remove`

Response:

```json
{ "success": 1 }
```

## stories/merge (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/merge`

Merge one story into another story within this controversy.

### Query Parameters

(no parameters)

### Input Description

| Field           | Description                              |
| --------------- | ---------------------------------------- |
| from_stories_id | id of the story to merge into to_stories_id; required |
| to_stories_id   | id of the story into which from_stories_id will be merge; required |

Merging from_stories_id into to_stories_id removes from_stories_id from the controversy and merges the outlinks and inlinks of from_stories_id into to_stories_id.

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the story was successfully merged. |

### Example

Merge story 1234 into story 6789:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/merge`

Input:

```json
{
  "from_stories_id": 1234,
  "to_stories_id": 6789
}
```

Response:

```json
{ "success": 1 }
```

# Sentences

## sentences/count

`https://api.mediacloud.org/api/v2/topics/~topics_id~/sentences/count`

Return the numer of sentences that match the query, optionally split by date.

This call behaves exactly like the main api sentences/count call, except:

- This call only searches within the given snapshot
- This call accepts the standard topics parameters: snapshots_id, frames_id, timespans_id

For details about this end point, including parameters, output, and examples, see the [main API](https://github.com/berkmancenter/mediacloud/blob/release/doc/api_2_0_spec/api_2_0_spec.md#apiv2sentencescount).

# Media

## media/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/media/list`

The media list call returns the list of media in the topic.

### Query Parameters

| Parameter | Default | Notes                                    |
| --------- | ------- | ---------------------------------------- |
| media_id  | null    | return only the specified media          |
| sort      | inlink  | sort field for returned stories; possible values: `inlink`, `social` |
| name      | null    | search for media with the given name     |
| limit     | 20      | return the given number of media         |
| link_id   | null    | return media using the paging link       |

If the `name` parameter is specified, the call returns only media sources that match a case insensitive search specified value. If the specified value is less than 3 characters long, the call returns an empty list.

Standard parameters accepted: snapshots_id, frames_id, timespans_id, limit, link_id.

### Output Description

| Field                | Description                              |
| -------------------- | ---------------------------------------- |
| media_id             | medium id                                |
| name                 | human readable label for medium          |
| url                  | medium url                               |
| story_count          | number of stories in medium              |
| inlink_count         | sum of the inlink_count for each story in the medium |
| outlink_count        | sum of the outlink_count for each story in the medium |
| bitly_click_count    | sum of the bitly_click_count for each story in the medium |
| facebook_share_count | sum of the facebook_share_count for each story in the medium |
| frame_ids            | list of ids of frames to which this medium belongs |

### Example

Return all stories in the medium that match 'twitt':

`https://api.mediacloud.org/api/v2/topics/~topics_id~/media/list?name=twitt`

Response:

```json
{
    "media":
    [
        {
            "bitly_click_count": 303,
            "media_id": 18346,
            "story_count": 3475,
            "name": "Twitter",
            "inlink_count": 8454,
            "url": "http://twitter.com",
            "outlink_count": 72,
            "facebook_share_count": 123
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
## media/~media_id~/edit (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/media/~media_id~/edit`

Edit and return the given media source.  Media source edits apply to that media source for all controversies.

### Query Parameters

(no parameters)

### Input Description

| Field                 | Description                              |
| --------------------- | ---------------------------------------- |
| media_id              | id of medium to edit; required           |
| name                  | name of medium                           |
| url                   | url of medium                            |
| has_foreign_rss_links | boolean indicating that many of the links in this source's rss feeds are to external sources |

### Example

Edit the name of media_id 1:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/media/~media_id~/edit`

Input:

```json
{
  "media_id": 1,
  "name": "The New York Times"
}
```

Output:

(see media/list)

## media/~media_id~/remove (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/media/~media_id~/remove`

Remove the given medium from the topic (but do not delete it from Media Cloud).

### Query Parameters

(no parameters)

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the medium was removed |

### Example

Remove media_id 1 from the topics_id 1340:

`https://api.mediacloud.org/api/v2/topics/1340/media/1/remove`

Response:

```json
{ "success": 1 }
```

## media/merge (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/media/merge`

Merge all stories from one medium into another medium within this topic.

### Query Parameters

(no parameters)

### Input Description

| Field         | Description                              |
| ------------- | ---------------------------------------- |
| from_media_id | id of the medium to merge into to_media_id; required |
| to_media_id   | id of the medium into which from_media_id will be merge; required |

Mergin from_media_id into to_media_id merges all stories of from_media_it into to_media_id.  If a story with a matching url or title already exists in to_media_id, the call merges those stories as described in stories/merge.  If no matching story exists in to_media_id, a new story is created.

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the story was successfully merged. |

### Example

Merge medium 1 into medium 2:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/media/merge`

Input:

```json
{
  "from_media_id": 1,
  "to_media_id": 2
}
```

Response:

```json
{ "success": 1 }
```

# Word Counts

## wc/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/wc/list`

Returns sampled counts of the most prevalent words in a topic, optionally restricted to sentences that match a given query.

This call behaves exactly like the main api wc/list call, except:

* This call only searches within the given snapshot
* This call accepts the standard topics parameters: snapshots_id, frames_id, timespans_id

For details about this end point, including parameters, output, and examples, see the [main API](https://github.com/berkmancenter/mediacloud/blob/release/doc/api_2_0_spec/api_2_0_spec.md#apiv2wclist).

<!-- RB - How do I find out what frames a particular word appears in most often? -->
<!-- HR - This would be pretty hard.  The only way to do this is to run a solr query for the word for each frame.  That
could have somewhat reasonable performance for a handful of frames, but I can't work my head around how to do it
with reasonable performance with hundreds of frames, and I can imagine the tag set frame sets we've proposed having
hundreds of frames. -->

# Frames

A *frame* is a set of stories identified through some *framing method*.  *Frame Sets* are sets of *frames* that share a *framing method* and are also usually some substantive theme determined by the user.  For example, a 'U.S. 2016 Election' topic might include a 'Candidates' *frame set* that includes 'trump' and 'clinton' frames, each of which uses a 'Boolean Query' *framing methodology* to identify stories relevant to each candidate with a separate boolean query for each.

A specific *frame* exists within a specific *snapshot*.  A single topic might have many 'clinton' *frames*, one for each *snapshot*.  Each *topic* has a number of *frame definion*, each of which tells the system which *frames* to create each time a new *snapshot* is created.  *Frames* for new *frame definitions* will be only be created for *snapshots* created after the creation of the *frame definition*.

The relationship of these objects is show"below":

*                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             topic
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            *       frame set definition
*                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             frame definition (+ framing method)
*                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             snapshot
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          *     frame set
*                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             frame (+ framing method)

## Framing Methods

Media Cloud currently supports the following framing methods.

* Boolean Query

Details about each framing method are below.  Among other properties, each framing method may or not be exclusive.  Exlcusive framing methods generate *frame sets* in which each story belongs to at most one *frame*.

### Framing Method: Boolean Query

The Boolean Query framing method associates a frame with a story by matching that story with a solr boolean query.  *Frame Sets* generated by the Boolean Query method are not exclusive.

## frame_set_definitions/create (POST)

`https://api.mediacloud.org/api/topics/~topics_id~/frame_sets/create`

Create and return a new *frame set definiition*  within the given *topic*.

### Query Parameters

(no parameters)

### Input Description

| Field          | Description                              |
| -------------- | ---------------------------------------- |
| name           | short human readable label for frame set definition |
| description    | human readable description of frame set definition |
| framing_method | framing method to be used for all frame definitions in this definition |

### Example

Create a 'Candidates' frame set definiition in the 'U.S. 2016 Election' topic:

`https://api.mediacloud.org/api/v2/topics/1344/frame_set_definitions_create`

Input:

```json
{
    "name": "Candidates",
    "description": "Stories relevant to each candidate.",
    "framing_methods": "Boolean Query"
}
```
Response:

```json
{
    "frame_set_definitions":
    [
        {
            "frame_set_definitions_id": 789,
            "topics_id": 456,
            "name": "Candidates",
            "description": "Stories relevant to each candidate.",
            "framing_method": "Boolean Query",
            "is_exclusive": 0
        }
    ]
}
```

## frame_set_definitions/~frame_set_definitions_id~/update (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/frame_set_definitions/~frame_set_definitions_id~/update/`

Update the given frame set definition.

### Query Parameters

(no parameters)

### Input Parameters

See *frame_set_definitions/create* for a list of fields.  Only fields that are included in the input are modified.

### Example

Update the name and description of the 'Candidates'  frame set"definition":

`https://api.mediacloud.org/api/v2/topics/1344/frame_set_definitions/789/update`

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
    "frame_set_definitions":
    [
        {
            "frame_set_definitions_id": 789,
            "topics_id": 456,
            "name": "Major Party Candidates",
            "description": "Stories relevant to each major party candidate.",
            "framing_method": "Boolean Query",
            "is_exclusive": 0
        }
    ]
}
```

## frame_set_definitions/~frame_set_definitions_id~/delete (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/frame_set_definitions/~frame_set_definitions_id~/delete`

Delete a frame set definition.

### Query Parameters

(no parameters)

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the frame set defintion was deleted. |

### Example

Delete frame_set_definitions_id 123:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/frame_set_definitions/123/delete`

Response:

```json
{ "success": 1 }
```

## frame_set_definitions/list

<!-- RB - who needs to consume this end point? I don't think I ever do... If the core engine is the only one that ever needs this engine then should it exist? -->
<!-- HR - I think you misunderstand the architecture I'm proposing.  

When I tried to write this api, I realized that we had to distinguish between the data that the system generates for
the frames and frame sets and the configuration data that the user creates to tell the system what data to generate.  If
we have only a frame set object in the api, how do we update or delete existing frame sets after we have run one
snapshot?  If we have just frame set object and not the definition and we delete a frame set, that would also
delete the frame in all of the snapshots.

So the idea is that the user will edit the frame set definitions to tell the system what frame sets to generate
each time a snapshot is generated.  I considered calling them 'frame set templates', which might be clearer?

Another way I could have done this is to have the 'frame set' objects be the templates and and then have 'snapshot
frame set' objects that have the actual data in them.  But the idea of a 'frame set definition' seems cleaner and
clearer than a 'snapshot frame set'. -->

`https://api.mediacloud.org/api/v2/topics/~topics_id~/frame_set_definitions/list`

Return a list of all frame set definitions belonging to the given topic.

### Query Parameters

(no parameters)

### Output Description

| Field                    | Description                              |
| ------------------------ | ---------------------------------------- |
| frame_set_definitions_id | frame set defintion id                   |
| name                     | short human readable label for the frame set definition |
| description              | human readable description of the frame set definition |
| framing_method           | framing method used for frames in this set |
| is_exclusive             | boolean that indicates whether a given story can only belong to one frame, based on the framing method |

### Example

List all frame set definitions associated with the 'U.S. 2016 Elections'"topic":

`https://api.mediacloud.org/api/v2/topics/1344/frame_set_definitions/list`

Response:

```json
{
    "frame_set_definitions":
    [
        {
            "frame_set_definitions_id": 789,
            "topics_id": 456,
            "name": "Major Party Candidates",
            "description": "Stories relevant to each major party candidate.",
            "framing_method": "Boolean Query",
            "is_exclusive": 0
        }
    ]
}
```

## frame_sets/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/frame_sets/list`

List all *frame sets* belonging to the current *snapshot* in the given *topic*.

### Query Parameters

Standard parameters accepted: snapshots_id.

If no snapshots_id is specified, the latest snapshot will be used.

### Output Description

| Field          | Description                              |
| -------------- | ---------------------------------------- |
| frame_sets_id  | frame set id                             |
| name           | short human readable label for the frame set |
| description    | human readable description of the frame set |
| framing_method | framing method used to generate the frames in the frame set |
| is_exclusive   | boolean that indicates whether a given story can only belong to one frame, based on the framing method |
| frames         | list of frames belonging to this frame set |

### Example

Get a list of *frame sets* in the latest *snapshot* in the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/frame_sets_list`

Response:

```json
{
    "frame_sets":
    [
        {
            "frame_sets_id": 34567,
            "name": "Candidates",
            "description": "Stories relevant to each candidate.",
            "framing_method": "Boolean Query",
            "is_exclusive": 0,
            "frames":
            [
                {
                    "frames_id": 234,
                    "name": "Clinton",
                    "description": "stories that mention Hillary Clinton",
                    "query": "clinton and ( hillary or -bill )",
                    "framing_method": "Boolean Query"
                }
            ]
        }
    ]
}
```


## frame_definitions/~frame_set_definitions_id~/create (POST)

`https://api.mediacloud.org/api/topics/~topics_id~/frame_sets/~frame_set_definitions_id~/create/`

Create and return a new *frame definiition*  within the given *topic* and *frame set definition*.

### Query Parameters

(no parameters)

### Input Description

| Field       | Description                              |
| ----------- | ---------------------------------------- |
| name        | short human readable label for frames generated by this definition |
| description | human readable description for frames generated by this definition |
| query       | Boolean Query: query used to generate frames generated by this definition |

The input for the *frame definition* depends on the framing method of the parent *frame set definition*.  The framing method specific input fields are listed last in the table above and are prefixed with the name of applicable framing method.

### Example

Create the 'Clinton' *frame definition* within the 'Candidates' *frame set definition* and the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/frame_definitions/789/create`

Input:

```json
{
    "name": "Clinton",
    "description": "stories that mention Hillary Clinton",
    "query": "clinton"
}
```

Response:

```json
{
    "frame_definitions":
    [
        {
            "frame_definitions_id": 234,
            "name": "Clinton",
            "description": "stories that mention Hillary Clinton",
            "query": "clinton",
            "framing_method": "Boolean Query"
        }
    ]
}
```


## frame_definitions/~frame_definitions_id~/update (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/frame_definitions/~frame_definitions_id~/update`

Update the given frame definition.

### Query Parameters

(no parameters)

### Input Description

See *frame_definitions/create* for a list of fields.  Only fields that are included in the input are modified.

### Example

Update the query for the 'Clinton' frame definition:

`https://api.mediacloud.org/api/v2/topics/1344/frame_definitions/234/update`

Input:

```json
{ "query": "clinton and ( hillary or -bill )" }
```

Response:

```json
{
    "frame_definitions":
    [
        {
            "frame_definitions_id": 234,
            "name": "Clinton",
            "description": "stories that mention Hillary Clinton",
            "query": "clinton and ( hillary or -bill )"
        }
    ]
}
```

## frame_definitions/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/frame_definitions/~frame_set_definitions_id~/list`

List all *frame definitions* belonging to the given *frame set definition*.

### Query Parameters

(no parameters)

### Output Description

| Field       | Description                              |
| ----------- | ---------------------------------------- |
| name        | short human readable label for frames generated by this definition |
| description | human readable description for frames generated by this definition |
| query       | Boolean Query: query used to generate frames generated by this definition |

The output for *frame definition* depends on the framing method of the parent *frame set definition*.  The framing
method specific fields are listed last in the table above and are prefixed with the name of applicable framing method.

### Example

List all *frame definitions* belonging to the 'Candidates' *frame set definition* of the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/frame_definitions/234/list`

Response:

```json
{
    "frame_definitions":
    [
        {
            "frame_definitions_id": 234,
            "name": "Clinton",
            "description": "stories that mention Hillary Clinton",
            "query": "clinton and ( hillary or -bill )"
        }
    ]
}
```

## frames/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/frame_sets/~frame_sets_id~/frames/list`

Return a list of the *frames* belonging to the given *frame set*.

### Query Parameters

(no parameters)

### Ouput Description

| Field       | Description                              |
| ----------- | ---------------------------------------- |
| frames_id   | frame id                                 |
| name        | short human readable label for the frame |
| description | human readable description of the frame  |
| query       | Boolean Query: query used to generate the frame |

The output for *frame* depends on the framing method of the parent *frame definition*.  The framing method specific fields are listed last in the table above and are prefixed with the name of applicable framing method.

### Example

Get a list of *frames* wihin the 'Candiates' *frame set* of the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/frame_sets/34567/frames/list`

Response:

```json
{
    "frames":
    [
        {
            "frames_id": 234,
            "name": "Clinton",
            "description": "stories that mention Hillary Clinton",
            "query": "clinton and ( hillary or -bill )",
            "framing_method": "Boolean Query"
        }
    ]
}
```

# Snapshots

Each *snapshot* contains a static copy of all data within a topic at the time the *snapshot* was made.  All data viewable by the Topics API must be viewed through a *snapshot*.

## snapshots/generate (POST)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/snapshots/generate`

Generate and return a new *snapshot* for the given topic.

This is an asynchronous call.  The *snapshot* process will run in the background, and the new *snapshot* will only become visible to the API once the generation is complete.  Only one *snapshot* generation job can run at a time.

<!-- RB - what happens if two people are working on separate frame definitions, but one finishes and presses the button that calls snapshots/generate?  will the other person's half-finished frame set be included in the new snapshot?  I guess I need to queue up all the frame definitions while someone is working on them until they press the big "generate" button, and then make a bunch of create calls before the snapshots/generate call. -->
<!-- HR - I think you are overengineering this.  I think it will be rare to edit frames over the life of a topic,
it will be rare for more than one person to edit a topic ever, and it will be vanishingly rare for two users to edit
the frames for a topic concurrently. If we get complaints, we can start worrying about atomic frame editing. -->

### Query Parameters

(no parameters)

### Input Description

| Field | Description                              |
| ----- | ---------------------------------------- |
| notes | short text notes about the snapshot; optional |

### Output Description

(see snapshots/list)

### Example

Start a new *snapshot* generation job for the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/snapshots/generate`

Response:

(see snapshots/list)

### snapshots/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/snapshots/list`

Return a list of all completed *snapshots* in the given *topic*.

### Query Paramaters

(no parameters)

### Output Description

| Field         | Description                           |
| ------------- | ------------------------------------- |
| snapshots_id  | snapshot id                           |
| snapshot_date | date on which the snapshot was create |
| notes         | short text notes about the snapshot   |

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
            "notes": "final snapshot for paper analysis"
        }  
    ]
}
```
<!-- TODO - I bet it will be useful to include the username here that generated it -->

## snapshots/~snapshots_id~/edit (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/snapshots/~snapshots_id~/edit`

Edit and return the snapshot.

### Query Parameters

(no parameters)

### Input Description

| Field        | Description                         |
| ------------ | ----------------------------------- |
| snapshots_id | snapshot id; required               |
| notes        | short text notes about the snapshot |

### Output Description

(see snapshots/list)

### Example

Edit the notes for snapshot 4567:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/snapshots/~snapshots_id~/edit`

Input:

```json
{
  "snapshots_id": 4567,
  "notes": "final snapshot for paper analysis"
}
```

Response:

(see snapshots/list)

# Timespans

Each *timespan* is a view of the *topic* that presents the topic as if it consists only of *stories* within the date range of the given *timespan*.

A *story* is included within a *timespan* if the publish_date of the story is within the *timespan* date range or if the *story* is linked to by a *story* that whose publish_date is within date range of the *timespan*.

## timespans/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/timespans/list`

Return a list of timespans in the current snapshot.

### Query Parameters

Standard parameters accepted: snapshots_id, frames_id.
<!-- RB - why does this accept frames_id? -->
<!-- HR - remember the hierarchy!  timespan belongs to frame belongs to snapshot.  to implement alexis' slider,
you'll be on a page for a given frame and need the list of timespans that belong to that frame -->

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
| model_r2_sd       | timespan modeling r2 standard deviation  |
| top_media         | number of media include in modeled top media list |

Every *topic* generates the following timespans for every *snapshot*:

* overall - an timespan that includes every story in the topic
* custom all - a custom period timespan that includes all stories within the date range of the topic
* weekly - a weekly timespan for each calendar week in the date range of the topic
* monthly - a monthly timespan for each calendar month in the date range of the topic

Media Cloud needs to guess the date of many of the stories discovered while topic spidering.  We have validated the date guessing to be about 87% accurate for all methods other than the finding a url in the story url.  The possiblity of significant date errors make it possible for the Topic Mapper system to wrongly assign stories to a given timespan and to also miscount links within a given timespan (due to stories getting misdated into or out of a given timespan).  To mitigate the risk of drawing the wrong research conclusions from a given timespan, we model what the timespan might look like if dates were wrong with the frequency that our validation tell us that they are wrong within a given timespan.  We then generate a pearson's correlation between the ranks of the top media for the given timespan in our actual data and in each of ten runs of the modeled data.  The model_* fields provide the mean and standard deviations of the square of those correlations.

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
            "model_r2_sd": 0.04,
            "top_media": 143
        }
    ]
}
```
<!-- RB - does this include timespans queued up for the next spanshot? if so, please add a "status" column indicating if the timespan is valid or not.  if it doesn't include does, how do I list them to show the user?  Maybe after they create one I just say "you need to generate a new snapshot to see this"... but then if they click away that information is long gone for them. -->
<!-- HR - there should be a timespans/list_dates call -->


## timespans/add_dates (PUT)
<!-- RB - for consistency, do we want to call this a timespan_definition?  and have the url end with /timespan_definitions/create -->
<!-- HR - I'm note sure.  the dates are simpler, so I thought I could get away with not making them first class
objects with ids.  We don't need to delete them. That seems simpler to me, but if consistency is more important
I'm fine with that. -->

`https://api.meiacloud.org/api/v1/topics/~topics_id~/timespans/add_dates`

Add a date range for which to generate *timespans* for future *spanshots*.

### Query Parameters

(no parameters)

### Input Description

| Field      | Description         |
| ---------- | ------------------- |
| start_date | start of date range |
| end_date   | end of date range   |

### Output Description

The output of this command is identical to a call to stories/list with the given stories_id.

### Example

Add a new *timespan* date range to 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/timespans/add_dates`

Input:

```json
{
    "start_date": "2016-02-01",
    "end_date": "2016-05-01"
}
```

Response:

```json
{ "success": 1 }
```

## timespans/list_dates

`https://api.mediacloud.org/api/v2/topics/~topics_id~/timespans/list_dates`

List the dates for which timespans will be generated for each new snapshot.

### Query Parameters

(no parameters)

### Output Description

| Field      | Description                      |
| ---------- | -------------------------------- |
| start_date | start of timespan date range     |
| end_date   | end of timespan date range       |
| period     | 'weekly', 'monthly', or 'custom' |

### Example

List all timespans for the 'U.S. Election 2012' topic:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/timespans/list_dates`

Response:

```json
{
  "dates":
  [
    {
      "start_date": "2016-01-01",
      "end_date": "2016-01-07",
      "period": "weekly"
    }
  ]
}
```



# TODO

* topics ACLs
* link and network graphing endpoints
* media source coding
* machline learning
