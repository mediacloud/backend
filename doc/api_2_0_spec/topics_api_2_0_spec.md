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
*media* that published those *stories*, and social media metrics about the *stories* and *media.  The various topics/
end points provide access to all of this raw data as well as various of various analytical processes applied to this
data.

## API URLs

All urls in the topics api are in the form:

`https://api.mediacloud.org/api/v2/topics/<topics_id>/stories/list?key=KEY`

For example, the following will return all stories in the latest snapshot of topic id 1344.

`https://api.mediacloud.org/api/v2/topics/1344/stories/list?key=KEY`

## Snapshots, Timespans, and Frames

Each *topic* is viewed through one of its *snapshots*.  A *snapshot* is static dump of all data from a topic at
a given point in time.  The data within a *snapshot* will never change, so changes to a *topic* are not visible
until a new *snapshot* is made.

Within a *snapshot*, data can be viewed overall, or through some combination of a *frame* and a *timespan*.

A *frame* consists of a subset of stories within a *topic* defined by some user configured *framing method*.  For
example, a 'trump' *frame* within a 'US Election' *topic* would be defined using the 'Boolean Query' *framing method*
as all stories matching the query 'trump'.  *Frames* can be collected together in a *Frame Set* for easy comparison.

A *timespan* displays the *topic* as if it exists only of stories either published within the date range of the
*timespan* or linked to by a story published within the date range of the *timespan*.

*Topics*, *snapshots*, *frames*, and *timespans* are strictly hierarchical.  Every *snapshot* belongs to a single
*topic*.  Every *frame* belongs to a single *snapshot*, and every timespan* belongs to either a single *frame* or the
*null *frame*.  Specifying a *frame* implies the parent *snapshot* of that *frame*.  Specifying a *topic* implies the
*parent *frame* (and by implication the parent *snapshot*), or else the null *frame* within the parent *snapshot*.

Every url that returns data from a *topic* accepts optional *spanshots_id*, *timespans_id*, and *frames_id* parameters.

If no *snapshots_id* is specified, the call returns data from the latest *snapshot* generated for the *topic*.  If no
*timespans_id* is specified, the call returns data from the overall *timespan* of the given *snapshot* and *frame*.  If
no *frames_id* is specified, the call assumes the null *frame*.  If multiple of these parameters are specified,
they must point to the same *topic* / *snapshot* / *frame* / *timespan* or an error will be returned (for instance, a
call that specifies a *snapshots_id* for a *snapshot* in a *topic* different from the one specified in the url, an error
will be returned).

## Paging

For calls that support paging, each url supports a *limit* parameter and a *continuation_id* paramter.  For these calls, only *limit* results will be returned at a time, and a set of *continuation_ids* will be returned along with the results.  To get the current set of results again, or the previous or next page of results, call the same end point with only the *key* and *continuation_id* parameters.  The *continuation_id* parameter includes state that remembers all of the parameters from the original call.

For example, the following a paged response:

 

```json
{
  stories:
  [ 
    {   
   	  stories_id: 168326235,
	  media_id: 18047,
	  bitly_click_count: 182,
      collect_date: "2013-10-26 09:25:39",
      publish_date: "2012-10-24 16:09:26",
      inlink_count: 531,
      language: "en",
      title: "Donald J. Trump (realDonaldTrump) on Twitter",
      url: "https://twitter.com/realDonaldTrump",
      outlink_count: 0,
      guid: "https://twitter.com/realDonaldTrump"
    }
  ],
  continuation_ids:
  {
    current: 123456,
    previous: 456789,
    next: 789123
  }
}

```

After receiving that reponse, you can use the following url with no other parameters to fetch the next page of results:

`https://api.mediacloud.org/api/v2/topics/1/stories/list?key=KEY&continuation_id=789123`

When the system has reached the end of the results, it will return an empty list and a null 'next' continuation_id.

Continuation ids are persistent and can be safely used to refer to a given result forever (for instance, as an identifier for a link shortener).

## Examples

The section for each end point includes an example call and response for that end point.  For end points that return multiple results, we generally only show a single result (for instance a single story) for the sake of documentation brevity.

# Topics

## topics/list

`https://api.mediacloud.org/api/v2/topics/list`

The topics/list call returns a simple list of topics available in Media Cloud.  The topics/list call is is only call
that does not include a topics_id in the url.

### Query Parameters

(no parameters)

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

### Example

Fetch all topics in Media Cloud:

`https://api.mediacloud.org/api/v2/topics/list`

Response:

```json
{
  topics:
  [
  	{
      topics_id: 672,
      name: "network neutrality",
      patern: "[[:<:]]net.*neutrality",
      solr_seed_query: "net* and neutrality and +tags_id_media:(8875456 8875460 8875107 8875110 8875109 8875111 8875108 8875028 8875027 8875114 8875113 8875115 8875029 129 2453107 8875031 8875033 8875034 8875471 8876474 8876987 8877928 8878292 8878293 8878294 8878332) AND +publish_date:[2013-12-01T00:00:00Z TO 2015-04-24T00:00:00Z]",
      solr_seed_query_run: 1,
      description: "network neutrality",
      max_iterations: 15
	}
  ]
}
```



# Stories

## stories/list

`https://api.mediacloud.org/api/v2/topics/<topics_id>/stories/list`

The stories list call returns stories in the topic.

### Query Parameters

| Parameter            | Default | Notes                                    |
| -------------------- | ------- | ---------------------------------------- |
| q                    | null    | if specified, return only stories that match the given solr query |
| sort                 | inlink  | sort field for returned stories; possible values: `inlink`, `social` |
| stories_id           | null    | return only stories matching these storie_ids |
| link_to_stories_id   | null    | return only stories from other media that link to the given stories_ids |
| link_from_stories_id | null    | return only stories from other media that are linked from the given stories_ids |
| media_id             | null    | return only stories belonging to the given media_ids |
| limit                | 20      | return the given number of stories       |
| continuation_id      | null    | return stories using the paging continuation |

The call will return an error if more than one of the following parameters are specified: `q`, `stories_id`, `link_to_stories`, `link_from_stories_id`, `media_id`.

For a detailed description of the format of the query specified in `q` parameter, see the entry for [stories_public/list](api_2_0_spec.md) in the main API spec.

The call also accepts the `limit` and `continuation_id` parameters.

### Output Description

| Field                | Description                              |
| -------------------- | ---------------------------------------- |
| stories_id           | story id                                 |
| media_id             | media source id                          |
| url                  | story url                                |
| title                | story title                              |
| guid                 | story globally unique identifier         |
| language             | two letter code for story language       |
| publish_date         | publication date of the story, or 'undateable' if the story is not dateable |
| collect_date         | date the story was collected             |
| date_guess_method    | method used to guess the publish_date    |
| inlink_count         | count of hyperlinks from stories in other media in this timespan |
| outlink_count        | count of hyperlinks to stories in other media in this timespan |
| bitly_click_count    | number of clicks on bitly links that resolve to this story's url |
| facebook_share_count | number of facebook shares for this story's url |

### Example

Fetch all stories in topic id 1344:

`https://api.mediacloud.org/api/v2/topics/1344/stories/list`

Response:

```json
{
  stories:
  [ 
    {   
   	  stories_id: 168326235,
	  media_id: 18047,
	  bitly_click_count: 182,
      collect_date: "2013-10-26 09:25:39",
      publish_date: "2012-10-24 16:09:26",
      date_guess_method: 'guess_by_og_article_published_time',
      inlink_count: 531,
      language: "en",
      title: "Donald J. Trump (realDonaldTrump) on Twitter",
      url: "https://twitter.com/realDonaldTrump",
      outlink_count: 0,
      guid: "https://twitter.com/realDonaldTrump"
    }
  ],
  continuation_ids:
  {
    current: 123456,
    previous: 456789,
    next: 789123
  }
}
```

## stories/count

`https://api.mediacloud.org/api/v2/topics/<topics_id>/stories/count`

Return the number of stories that match the query.

### Query Parameters

| Parameter | Default | Notes                               |
| --------- | ------- | ----------------------------------- |
| q         | null    | count stories that match this query |

For a detailed description of the format of the query specified in `q` parameter, see the entry for [stories_public/list](https://github.com/berkmancenter/mediacloud/blob/release/doc/api_2_0_spec/api_2_0_spec.md#apiv2stories_publiclist) in the main API spec.

### Output Description

| Field | Description                |
| ----- | -------------------------- |
| count | number of matching stories |

### Example

Return the number of stories that mention 'immigration' in the 'US Election' topic:

`https://api.mediacloud.org/api/v2/topics/<topics_id>/stories_count?q=immigration`

Response:

```json
{
  count: 123
}
```

# Sentences

## sentences/count

`https://api.mediacloud.org/api/v2/topics/<topics_id>/sentences/count`

Return the numer of sentences that match the query, optionally split by date.

The topics `sentences/count` call is identical to the `sentences/count` call in the main API, except that the topics version accepts the snapshots_id, frames_id, and timespans_id parameters and returns counts only for stories within the topic.

For details about this end point, including parameters, output, and examples, see the [main API](https://github.com/berkmancenter/mediacloud/blob/release/doc/api_2_0_spec/api_2_0_spec.md#apiv2sentencescount).

# Media

## media/list

`https://api.mediacloud.org/api/v2/topics/<topics_id>/media/list`

The media list call returns the list of media in the topic.

### Query Parameters

| Parameter       | Default | Notes                                    |
| --------------- | ------- | ---------------------------------------- |
| media_id        | null    | return only the specified media          |
| sort            | inlink  | sort field for returned stories; possible values: `inlink`, `social` |
| name            | null    | search for media with the given name     |
| limit           | 20      | return the given number of media         |
| continuation_id | null    | return media using the paging continuation |

If the `name` parameter is specified, the call returns only media sources that match a case insensitive search specified value. If the specified value is less than 3 characters long, the call returns an empty list.

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

### Example

Return all stories in the medium that match 'twitt':

`https://api.mediacloud.org/api/v2/topics/<topics_id>/media/list?name=twitt`

Response:

```json
{
  media: 
  [
    {
      bitly_click_count: 303,
      media_id: 18346,
      story_count: 3475,
      name: "Twitter",
      inlink_count: 8454,
      url: "http://twitter.com",
      outlink_count: 72,
      facebook_share_count: 123
    }
  ],
  continuation_ids:
  {
    current: 123456,
    previous: 456789,
    next: 789123
  }
}
```



