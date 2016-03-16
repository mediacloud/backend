% Media Cloud API Version 2
%

# Authentication

Every call below includes a `key` parameter which will authenticate the user to the API service.  The key parameter is excluded
from the examples in the below sections for brevity.

To get a key, register for a user:

https://core.mediacloud.org/login/register

Once you have an account go here to see your key:

https://core.mediacloud.org/admin/profile

### Example

https://api.mediacloud.org/api/v2/media/single/1?key=KRN4T5JGJ2A


## Request Limits

Each user is limited to 1,000 API calls and 20,000 stories returned in any 7 day period.  Requests submitted beyond this
limit will result in a status 403 error.  Users who need access to more requests should email info@mediacloud.org.

#Python Client

A [Python client]( https://github.com/c4fcm/MediaCloud-API-Client ) for our API is now available. Users who develop in Python will probably find it easier to use this client than to make web requests directly.
The Python client is available [here]( https://github.com/c4fcm/MediaCloud-API-Client ).

#API URLs

*Note:* by default the API only returns a subset of the available fields in returned objects. The returned fields are those that we consider to be the most relevant to users of the API. If the `all_fields` parameter is provided and is non-zero, then a more complete list of fields will be returned. For space reasons, we do not list the `all_fields` parameter on individual API descriptions.

## Errors

The Media Cloud returns an appropriate HTTP status code for any error, along with a json document in the following format:

```json
{ "error": "error message" }
```

## Request Limits

Each user is limited to 1,000 API calls and 20,000 stories returned in any 7 day period.  Requests submitted beyond this
limit will result in a status 403 error.  Users who need access to more requests should email info@mediacloud.org.

## Python Client

We use a python client library to access the api for our own work (including the dashboard implementation at
dashboard.mediameter.org).  That library is available on [github](https://github.com/c4fcm/MediaCloud-API-Client).

## Media

The Media api calls provide information about media sources.  A media source is a publisher of content, such as the New York
Times or Instapundit.  Every story belongs to a single media source.  Each media source can have zero or more feeds.

### api/v2/media/single/

| URL                              | Function
| -------------------------------- | -------------------------------------------------------------
| `api/v2/media/single/<media_id>` | Return the media source in which `media_id` equals `<media_id>`

#### Query Parameters

None.

#### Example

Fetching information on The New York Times

URL: https://api.mediacloud.org/api/v2/media/single/1

Response:

```json
[
  {
    "url": "http:\/\/nytimes.com",
    "name": "New York Times",
    "media_id": 1,
    "media_source_tags": [
         {
           "tag_sets_id": 5,
           "show_on_stories": null,
           "tags_id": 8875027,
           "show_on_media": 1,
           "description": "Top U.S. mainstream media according Google Ad Planner's measure of unique monthly users.",
           "tag_set": "collection",
           "tag": "ap_english_us_top25_20100110",
           "label": "U.S. Mainstream Media"
         }
    ],
  }
]
```

## Media Health

BETA - The media health feature is in beta.  The fields returned and the definitions of those fields may
change in the future.

The Media Health api call provides information about the health of a media source, meaning to what degree we are
capturing all of the stories published by that media source.  Media Cloud collects its data via
automatically detected rss feeds on the open web.  This means first that the system generally has data for a given
media source from the time we first enter that source into our database.  Second, Media Cloud data for a given media
source is only as good as the set of feeds we have for that source.  Our feed scraper is not perfect and so sometimes
misses feeds it should be collecting.   Third, feeds change over time.  We periodically rescrape every media source
for new feeds, but this takes time and is not perfect.

The only way we have of judging the health is judging the relative number of stories over time.  This media call
provides a set of metrics that compare the current number of stories being collected by the media source with
the number of stories collected over the past 90 days, and also compares coverage over time with the expected
volume.  More details are in the field descriptions below

### api/v2/mediahealth/list

| URL                              | Function
| -------------------------------- | -------------------------------------------------------------
| `api/v2/mediahealth/list`        | Return media health data for the given media sources

#### Query Parameters

| Parameter                         | Default | Notes
| --------------------------------- | ------- | -----------------------------------------------------------------
| `media_id`                        | none    | Return health data for the given media sources. May be specified multiple times.

### Output description

| Field               | Description
| ------------------- | ----------------------------------------------------------------------
| `media_id`          | The id of the media source
| `is_healthy`        | Is the media source currently returning at least 25% of the 90 day averages of stories and sentences
| `has_active_feed`   | Does the media source have at least one active syndicated feed (which may not be returning any stories)
| `num_stories`       | Number of stories collected yesterday
| `num_stories_w`     | Average number of stories collected in the last 7 days
| `num_stories_90`    | Average number of stories collected in the last 90 days
| `num_stories_y`     | Average number of stories collected in the last year
| `num_sentences`     | Number of sentences collected yesterday
| `num_sentences_w`   | Average number of sentences collected in the last 7 days
| `num_sentences_90`  | Average number of sentences collected in the 90 days
| `num_sentences_y`   | Average number of sentences collected in the last year
| `expected_stories`  | Average number of stories collected for each of the 20 days with the highest number of stories
| `expected_sentences`| Average number of sentences collected or each of the 20 days with the highest number of sentences
| `start_date`        | First week on which at least 25% of expected_stories and expected_sentences were collected
| `end_date`          | Last week on which at least 25% of expected_stories and expected_sentences were collected
| `coverage_gaps`     | Number of weeks between start_date and end_date for which fewer than 25% of expected_stories or expected_sentences were collected
| `coverage_gaps_list`| List of weeks between start_date and end_date for which fewer than 25% of expected_stories or expected_sentences were collected

#### Example

Fetch media health information for media source 4438:

https://api.mediacloud.org/api/v2/mediahealth/list?media_id=4438

Response:

```json
[
    {
        "media_id": "4438",
        "is_healthy": 1,
        "has_active_feed": 1,
        "num_stories": 42,
        "num_stories_w": "28.57",
        "num_stories_90": "30.54",
        "num_stories_y": "33.00",
        "num_sentences": 1200,
        "num_sentences_w": "873.86",
        "num_sentences_90": "877.16",
        "num_sentences_y": "926.83",
        "start_date": "2011-01-03 00:00:00-05",
        "end_date": "2016-02-22 00:00:00-05",
        "expected_stories": "49.97",
        "expected_sentences": "1166.22",
        "coverage_gaps": 1,
        "coverage_gaps_list": [
            {
                "media_id": "4438",
                "stat_week": "2013-12-23 00:00:00-05",
                "num_stories": "12.43",
                "num_sentences": "350.29",
                "expected_stories": "49.97",
                "expected_sentences": "1166.22",
            }
        ],
    }
]
```



### api/v2/media/list/

| URL                 | Function
| ------------------- | -----------------------------
| `api/v2/media/list` | Return multiple media sources

#### Query Parameters

| Parameter                         | Default | Notes
| --------------------------------- | ------- | -----------------------------------------------------------------
| `last_media_id`                   | 0       | Return media sources with a `media_id` greater than this value
| `rows`                            | 20      | Number of media sources to return. Cannot be larger than 100
| `name`                            | none    | Name of media source for which to search
| `controversy_dump_time_slices_id` | null    | Return media within the given controversy time slice
| `controversy_mode`                | null    | If set to 'live', return media from live controversies
| `tags_id`                         | null    | Return media associate with the given tag
| `q`                               | null    | Return media with at least one sentence that matches the solr query


If the name parameter is specified, the call returns only media sources that match a case insensitive search
specified value.  If the specified value is less than 3 characters long, the call returns an empty list.

If the controversy_dump_time_slices_id parameter is specified, return media within the given time slice,
sorted by descending inlink_count within the controversy time slice.  If controversy_mode is set to
'live', return media from the live controversy stories rather than from the frozen controversy dump.

If the 'q' parameter is specified, return only media that include at least on sentence that matches the given
solr query.  For a description of the solr query format, see the stories\_public/list call.

#### Example

URL: https://api.mediacloud.org/api/v2/media/list?last_media_id=1&rows=2

Output format is the same as for api/v2/media/single above.

## Feeds

A feed is either a syndicated feed, such as an RSS feed, or a single web page.  Each feed is downloaded between once
an hour and once a day depending on traffic.  Each time a syndicated feed is downloaded, each new URL found in the feed is
added to the feed's media source as a story.  Each time a web page feed is downloaded, that web page itself is added as
a story for the feed's media source.

Each feed belongs to a single media source.  Each story can belong to one or more feeds from the same media source.

### api/v2/feeds/single

| URL                              | Function
| -------------------------------- | --------------------------------------------------------
| `api/v2/feeds/single/<feeds_id>` | Return the feed for which `feeds_id` equals `<feeds_id>`

#### Query Parameters

None.

#### Example

URL: https://api.mediacloud.org/api/v2/feeds/single/1

```json
[
  {
    "name": "Bits",
    "url": "http:\/\/bits.blogs.nytimes.com\/rss2.xml",
    "feeds_id": 1,
    "feed_type": "syndicated",
    "media_id": 1
  }
]
```

### api/v2/feeds/list

| URL                 | Function
| ------------------- | --------------------------
| `api/v2/feeds/list` | Return multiple feeds

#### Query Parameters

| Parameter            | Default    | Notes
| -------------------- | ---------- | -----------------------------------------------------------------
| `last_feeds_id`      | 0          | Return feeds in which `feeds_id` is greater than this value
| `rows`               | 20         | Number of feeds to return. Cannot be larger than 100
| `media_id`           | (required) | Return feeds belonging to the media source

#### Example

URL: https://api.mediacloud.org/api/v2/feeds/list?media_id=1

Output format is the same as for api/v2/feeds/single above.

## Stories

A story represents a single published piece of content.  Each unique URL downloaded from any syndicated feed within
a single media source is represented by a single story.  For example, a single New York Times newspaper story is a
Media Cloud story, as is a single Instapundit blog post.  Only one story may exist for a given title for each 24 hours
within a single media source.

### Output description

The following table describes the meaning and origin of fields returned by both api/v2/stories_public/single and api/v2/stories_public/list.

| Field               | Description
| ------------------- | ----------------------------------------------------------------------
| `stories_id`        | The internal Media Cloud ID for the story.
| `media_id`          | The internal Media Cloud ID for the media source to which the story belongs.
| `media_name`        | The name of the media source to which the story belongs.
| `media_url`         | The url of the media source to which the story belongs.
| `publish_date`      | The publish date of the story as specified in the RSS feed.
| `tags`              | A list of any tags associated with this story, including those written through the write-back api.
| `collect_date`      | The date the RSS feed was actually downloaded.
| `url`               | The URL field in the RSS feed.
| `guid`              | The GUID field in the RSS feed. Defaults to the URL if no GUID is specified in the RSS feed.
| `language`          | The language of the story as detected by the chromium compact language detector library.
| `title`             | The title of the story as found in the RSS feed.
| `bitly_click_count` | The total Bit.ly click count within 30 days from the story's `publish_date` or `collect_date`, or `null` if the click count hasn't been collected yet.
| `ap_syndicated`     | Whether our detection algorithm thinks that this is an English language syndicated AP story


### api/v2/stories_public/single

| URL                                  | Function
| ------------------------------------ | ------------------------------------------------------
| `api/v2/stories_public/single/<stories_id>` | Return the story for which `stories_id` equals `<stories_id>`

#### Example

Note: This fetches data on the CC licensed Global Voices story ["Myanmar's new flag and new name"](http://globalvoicesonline.org/2010/10/26/myanmars-new-flag-and-new-name/#comment-1733161) from November 2010.

URL: https://api.mediacloud.org/api/v2/stories_public/single/27456565


```json
[
  {
    "collect_date": "2010-11-24 15:33:39",
    "url": "http:\/\/globalvoicesonline.org\/2010\/10\/26\/myanmars-new-flag-and-new-name\/comment-page-1\/#comment-1733161",
    "guid": "http:\/\/globalvoicesonline.org\/?p=169660#comment-1733161",
    "publish_date": "2010-11-24 04:05:00",
    "media_id": 1144,
    "media_name": "Global Voices Online",
    "media_url": "http:\/\/globalvoicesonline.org\/"
    "stories_id": 27456565,
    "story_tags": [ 1234235 ],
  }
]
```

### api/v2/stories_public/list

| URL                             | Function
| ------------------------------- | ---------------------------------
| `api/v2/stories_public/list` | Return multiple processed stories

#### Query Parameters

| Parameter                    | Default                | Notes
| ---------------------------- | ---------------------- | ------------------------------------------------------------------------------
| `last_processed_stories_id`  | 0                      | Return stories in which the `processed_stories_id` is greater than this value.
| `rows`                       | 20                     | Number of stories to return, max 10,000.
| `q`                          | null                   | If specified, return only results that match the given Solr query.  Only one `q` parameter may be included.
| `fq`                         | null                   | If specified, file results by the given Solr query.  More than one `fq` parameter may be included.
| `sort`                       | `processed_stories_id` | Returned results sort order. Supported values: <ul><li><code>processed_stories_id</code> - order results by processed stories ID (ascending);</li><li><code>bitly_click_count</code> - order results by Bit.ly click count (descending).</ul>


The `last_processed_stories_id` parameter can be used to page through these results. The API will return stories with a
`processed_stories_id` greater than this value.  To get a continuous stream of stories as they are processed by Media Cloud,
the user must make a series of calls to api/v2/stories_public/list in which `last_processed_stories_id` for each
call is set to the `processed_stories_id` of the last story in the previous call to the API.  A single call can only
return up to 10,000 results, but you can get the full list of results by paging through the full list using
`last_processed_stories_id`.

*Note:* `stories_id` and `processed_stories_id` are separate values. The order in which stories are processed is different than the `stories_id` order. The processing pipeline involves downloading, extracting, and vectoring stories. Requesting by the `processed_stories_id` field guarantees that the user will receive every story (matching the query criteria if present) in
the order it is processed by the system.

The `q` and `fq` parameters specify queries to be sent to a Solr server that indexes all Media Cloud stories.  The Solr
server provides full text search indexing of each sentence collected by Media Cloud.  All content is stored as individual
sentences.  The api/v2/stories_public/list call searches for sentences matching the `q` and / or `fq` parameters if specified and
the stories that include at least one sentence returned by the specified query.

The `q` and `fq` parameters are passed directly through to Solr.  Documentation of the format of the `q` and `fq` parameters is [here](http://lucene.apache.org/core/4_6_1/queryparser/org/apache/lucene/queryparser/classic/package-summary.html#package_description).  Below are the fields that may be used as solr query parameters, for example 'sentence:obama AND media_id:1':

| Field                        | Description
| ---------------------------- | -----------------------------------------------------
| sentence                     | the text of the sentence
| stories_id                   | a story ID
| media_id                     | the Media Cloud media source ID of a story
| publish_date                 | the publish date of a story
| tags_id_story                | the ID of a tag associated with a story
| tags_id_media                | the ID of a tag associated with a media source
| processed_stories_id         | the processed_stories_id as returned by stories_public/list

Be aware that ':' is usually replaced with '%3A' in programmatically generated URLs.

In addition, there following fields may be entered as pseudo queries within the solr query:

| Pseudo Query Field                        | Description
| ---------------------------- | -----------------------------------------------------
| controversy                  | a controversy id
| controversy_dump_time_slice  | a controversy dump time slice id
| link_from_tag                | a tag id, returns stories linked from stories associated with the tag
| link_to_story                | a story id, returns stories that link to the story
| link_from_story              | a story id, returns stories that are linked from the story
| link_to_medium               | a medium id, returns stories that link to stories within the medium
| link_from_medium             | link_from_medium, returns stories that are linked from stories within the medium

To include one of these fields in a larger solr query, delineate with {~ }, for example:

{~ controversy:1 } and media_id:1

The api will translate the given pseudo query into a stories_id: clause in the larger solr query.  So the above query
will be translated into the following, including controversy 1 consists of stories with ids 1, 2, 3, and 4.

stories_id:( 1 2 3 4 ) and media_id:1

If '-1' is appended to the controversy_dump_time_slice query field value, the pseudo query will match stories
from the live controversy matching the given time slice rather than from the dump.  For example, the following will
live stories from controversy_dump_time_slice 1234:

{~ controversy_dump_time_slice:1234-1 }

The link_* pseudo query fields all must be within the same {~ } clause as a controversy_dump_time_slice query and
return links from the associated controversy_dump_time_slice.  For example, the following returns stories that
link to story 5678 within the specified time slice:

{~ controversy_dump_time_slice:1234-1 link_to_story:5678 }

#### Example

The output of these calls is in exactly the same format as for the api/v2/stories_public/single call.

URL: https://api.mediacloud.org/api/v2/stories_public/list?last_processed_stories_id=8625915

Return a stream of all stories processed by Media Cloud, greater than the `last_processed_stories_id`.

URL: https://api.mediacloud.org/api/v2/stories_public/list?last_processed_stories_id=2523432&q=sentence:obama+AND+media_id:1

Return a stream of all stories from The New York Times mentioning `'obama'` greater than the given `last_processed_stories_id`.

## Sentences

The text of every story processed by Media Cloud is parsed into individual sentences.  Duplicate sentences within
the same media source in the same week are dropped (the large majority of those duplicate sentences are
navigational snippets wrongly included in the extracted text by the extractor algorithm).

### api/v2/sentences/count

#### Query Parameters

| Parameter          | Default          | Notes
| ------------------ | ---------------- | ----------------------------------------------------------------
| `q`                | n/a              | `q` ("query") parameter which is passed directly to Solr
| `fq`               | `null`           | `fq` ("filter query") parameter which is passed directly to Solr
| `split`            | `null`           | if set to 1 or true, split the counts into date ranges
| `split_start_date` | `null`           | date on which to start date splits, in YYYY-MM-DD format
| `split_end_date`   | `null`           | date on which to end date splits, in YYYY-MM-DD format

The q and fq parameters are passed directly through to Solr (see description of q and fq parameters in api/v2/stories_public/list section above).

The call returns the number of sentences returned by Solr for the specified query.

If split is specified, split the counts into regular date ranges for dates between split\_start\_date and split\_end\_date.
The number of days in each date range depends on the total number of days between split\_start\_date and split\_end\_date:

| Total Days | Days in each range
| ---------- | ------------------
| < 90       | 1 day
| < 180      | 3 days
| >= 180     | 7 days

Note that the total count returned by a split query is for all sentences found by the solr query, which query might or might not
include a date restriction.  So in the example africa query below, the 236372 count is for all sentences matching africa, not just those within the split date range.

#### Example

Count sentences containing the word 'obama' in The New York Times.

URL: https://api.mediacloud.org/api/v2/sentences/count?q=sentence:obama&fq=media_id:1

```json
{
  "count" => 96620
}
```

Count sentences containing 'africa' in the U.S. Mainstream Media from 2014-01-01 to 2014-03-01:

URL: https://api.mediacloud.org/api/v2/sentences/count?q=sentence:africa+AND+tags\_id\_media:8875027&split=1&split\_start\_date=2014-01-01&split\_end\_date=2014-03-01

```json
{
  "count": 236372,
  "split":
  {
    "2014-01-01T00:00:00Z": 650,
    "2014-01-08T00:00:00Z": 900,
    "2014-01-15T00:00:00Z": 999,
    "2014-01-22T00:00:00Z": 1047,
    "2014-01-29T00:00:00Z": 1125,
    "2014-02-05T00:00:00Z": 946,
    "2014-02-12T00:00:00Z": 1126
    "2014-02-19T00:00:00Z": 1094,
    "2014-02-26T00:00:00Z": 1218,
    "gap": "+7DAYS",
    "end": "2014-03-05T00:00:00Z",
    "start": "2014-01-01T00:00:00Z",
    }
}
````

### api/v2/sentences/field\_count

Returns the number of times a given field is associated with a given sentence.  Supported fields
are currently `tags_id_stories` and `tags_id_story_sentences`.

#### Query Parameters

| Parameter           | Default | Notes
| ------------------- | ---------------------------- | ----------------------------------------------------------------
| `q`                 | n/a                          | `q` ("query") parameter which is passed directly to Solr
| `fq`                | `null`                       | `fq` ("filter query") parameter which is passed directly to Solr
| `sample_size`       | 1000                         | number of sentences to sample, max 100,000
| `include_stats`     | 0                            | include stats about the request as a whole
| `field`             | `tags_id_story_sentences`    | field to count
| `tag_sets_id`       | `null`                       | return only tags belonging to the given tag set

See above /api/v2/stories_public/list for Solr query syntax.

If the field is set to `tags_id_story_sentences`, the call returns all of the tags associated with
sentences matching the query along with a count of how many times each tag is associated with each
matching sentence.  If the field is set to `tags_id_stories`, the call returns all of the tags associated with
story including a sentence matching the query along with a count of how many times each tag is associated with
each matching story.

To provide quick results, the api counts field values in a randomly sampled set of sentences returned
by the given query.  By default, the request will sample 1000 sentences.  You can make the api sample
more sentences (up to 100,000) at the cost of increased time.

Setting the 'stats' field to true changes includes the following fields in the response:

| Field                        | Description
| ---------------------------- | -------------------------------------------------------------------
| num_sentences_returned       | The number of sentences returned by the call, up to sample_size
| num_sentences_found          | The total number of sentences found by solr to match the query
| sample_size_param            | The sample size passed into the call, or the default value

#### Example

Gets the tag counts for all sentences containing the word `'obama'` in The New York Times

URL:  https://api.mediacloud.org/api/v2/sentences/field_count?q=obama+AND+media_id:1

```json
[
    {
        "count": "68",
        "tag_sets_id": 1011,
        "label": null,
        "tag": "geonames_2306104",
        "tags_id": 8881223
    },
    {
        "count": "39",
        "tag_sets_id": 1011,
        "label": null,
        "tag": "geonames_2300660",
        "tags_id": 8879465
    },
    {
        "count": "5",
        "tag_sets_id": 1011,
        "label": null,
        "tag": "geonames_6252001",
        "tags_id": 8878461
    }
]
```


## Word Counting

### api/v2/wc/list

Returns word frequency counts of the most common words in a randomly sampled set of all sentences
returned by querying Solr using the `q` and `fq` parameters, with stopwords removed by default.  Words are
stemmed before being counted.  For each word, the call returns the stem and the full term most used
with the given stem (for example, in the below example, 'democrat' is the stem that appeared
58 times and 'democrats' is the word that was most commonly stemmed into 'democract').

#### Query Parameters

| Parameter           | Default | Notes
| ------------------- | ------- | ----------------------------------------------------------------
| `q`                 | n/a     | `q` ("query") parameter which is passed directly to Solr
| `fq`                | `null`  | `fq` ("filter query") parameter which is passed directly to Solr
| `languages`         | `en`    | space separated list of languages to use for stopwording and stemming
| `num_words`         | 500     | number of words to return
| `sample_size`       | 1000    | number of sentences to sample, max 100,000
| `include_stopwords` | 0       | set to 1 to include stopwords in the listed languages
| `include_stats`     | 0       | set to 1 to include stats about the request as a whole (such as total number of words)

See above /api/v2/stories_public/list for Solr query syntax.

To provide quick results, the api counts words in a randomly sampled set of sentences returned
by the given query.  By default, the request will sample 1000 sentences and return 500 words.  You
can make the api sample more sentences.  The system takes about one second to process each multiple of
1000 sentences.

By default, the system stems and stopwords the list in English.  If you specify the 'l' parameter,
the system will stem and stopword the words by each of the listed langauges serially.  To do no stemming
or stopwording, specify 'none'.  The following language are supported (by 2 letter language code):
'da' (Danish), 'de' (German), 'en' (English), 'es' (Spanish), 'fi' (Finnish), 'fr' (French),
'hu' (Hungarian), 'it' (Italian), 'lt' (Lithuanian), 'nl' (Dutch), 'no' (Norwegian), 'pt' (Portuguese),
'ro' (Romanian), 'ru' (Russian), 'sv' (Swedish), 'tr' (Turkish).

Setting the 'stats' field to true changes the structure of the response, as shown in the example below.
Following fields are included in the stats response:

| Field                        | Description
| ---------------------------- | -------------------------------------------------------------------
| num_words_returned           | The number of words returned by the call, up to num_words
| num_sentences_returned       | The number of sentences returned by the call, up to sample_size
| num_sentences_found          | The total number of sentences found by solr to match the query
| num_words_param              | The num_words param passed into the call, or the default value
| sample_size_param            | The sample size passed into the call, or the default value

### Example

Get word frequency counts for all sentences containing the word `'obama'` in The New York Times

URL:  https://api.mediacloud.org/api/v2/wc/list?q=obama+AND+media_id:1

```json
[

  {
    "count":1014,
    "stem":"obama",
    "term":"obama"
  },
  {
    "count":106,
    "stem":"republican",
    "term":"republican"
  },
  {
    "count":78,
    "stem":"campaign",
    "term":"campaign"
  },
  {
    "count":72,
    "stem":"romney",
    "term":"romney"
  },
  {
    "count":59,
    "stem":"washington",
    "term":"washington"
  },
  {
    "count":58,
    "stem":"democrat",
    "term":"democrats"
  }
]
```

Get word frequency counts for all sentences containing the word `'obama'` in The New York Times, with
stats data included

URL:  https://api.mediacloud.org/api/v2/wc/list?q=obama+AND+media_id:1&stats=1

```json

{ "stats":
  {
     "num_words_returned":5123,
     "num_sentences_returned":899
     "num_sentences_found":899
   }
   "words":
   [
     {
       "count":1014,
       "stem":"obama",
       "term":"obama"
     },
     {
       "count":106,
       "stem":"republican",
       "term":"republican"
     },
     {
       "count":78,
       "stem":"campaign",
       "term":"campaign"
     },
     {
       "count":72,
       "stem":"romney",
       "term":"romney"
     },
     {
       "count":59,
       "stem":"washington",
       "term":"washington"
     },
     {
       "count":58,
       "stem":"democrat",
       "term":"democrats"
     }
   ]
}

```

## Tags and Tag Sets

Media Cloud associates tags with media sources, stories, and individual sentences.  A tag consists of a short snippet of text,
a `tags_id`, and `tag_sets_id`.  Each tag belongs to a single tag set.  The tag set provides a separate name space for a group
of related tags.  Each tag has a unique name ('tag') within its tag set.  Each tag set consists of a tag_sets_id and a uniaue
name.

For example, the `'gv_country'` tag set includes the tags `japan`, `brazil`, `haiti` and so on.  Each of these tags is associated with
some number of media sources (indicating that the given media source has been cited in a story tagged with the given country
in a Global Voices post).

### api/v2/tags/single/

| URL                              | Function
| -------------------------------- | -------------------------------------------------------------
| `api/v2/tags/single/<tags_id>`   | Return the tag in which `tags_id` equals `<tags_id>`

#### Query Parameters

None.

#### Output description

| Field                 | Description
|-----------------------|-----------------------------------
| tags_id               | Media Cloud internal tag ID
| tags\_sets\_id        | Media Cloud internal ID of the parent tag set
| tag                   | text of tag, often cryptic
| label                 | a short human readable label for the tag
| description           | a couple of sentences describing the meaning of the tag
| show\_on\_media       | recommendation to show this tag as an option for searching solr using the tags_id_media
| show\_on\_stories     | recommendation to show this tag as an option for searching solr using the tags_id_stories
| tag\_set\_name        | name field of associated tag set
| tag\_set\_label       | label field of associated tag set
| tag\_set\_description | description field of associated tag set

The show\_on\_media and show\_on\_stories fields are useful for picking out which tags are likely to be useful for
external researchers.  A tag should be considered useful for searching via tags\_id\_media or tags\_id\_stories
if show\_on\_media or show\_on\_stories, respectively, is set to true for _either_ the specific tag or its parent
tag set.

#### Example

Fetching information on the tag 8876989.

URL: https://api.mediacloud.org/api/v2/tags/single/8875027

Response:

```json
[
  {
    "tag_sets_id": 5,
    "show_on_stories": null,
    "label": "U.S. Mainstream Media",
    "tag": "ap_english_us_top25_20100110",
    "tags_id": 8875027,
    "show_on_media": 1,
    "description": "Top U.S. mainstream media according Google Ad Planner's measure of unique monthly users.",
    "tag_set_name": "collection",
    "tag_set_label": "Collection",
    "tag_set_description": "Curated collections of media sources"
  },
]
```

### api/v2/tags/list/

| URL                 | Function
| ------------------- | -----------------------------
| `api/v2/tags/list`  | Return multiple tags

#### Query Parameters

| Parameter       | Default    | Notes
| --------------- | ---------- | -----------------------------------------------------------------
| `last_tags_id`  | 0          | Return tags with a `tags_id` is greater than this value
| `tag_sets_id`   | none       | Return tags belonging to the given tag set.  The most useful tag set is tag set 5.
| `rows`          | 20         | Number of tags to return. Cannot be larger than 100
| `public`        | none       | If public=1, return only public tags (see below)
| `search`        | none       | Search for tags by text (see below)

If set to 1, the public parameter will return only tags that are generally useful for public consumption.  Those
tags are defined as tags for which show_on_media or show_on_stories is set to true for either the tag
or the tag's parent tag_set.  As described below in tags/single, a public tag can be usefully searched
using the solr tags_id_media field if show_on_media is true and by the tags_id_stories field if
show_on_stories is true.

If the search parameter is set, the call will return only tags that match a case insensitive search for
the given text.  The search includes the tag and label fields of the tags plus the names and label
fields of the associated tag sets.  So a search for 'politics' will match tags whose tag or
label field includes 'politics' and also tags belonging to a tag set whose name or label field includes
'politics'.  If the search parameter has less than three characters, an empty result set will be
returned.

#### Example

URL: https://api.mediacloud.org/api/v2/tags/list?rows=2&tag_sets_id=5&last_tags_id=8875026

### api/v2/tag_sets/single/

| URL                                    | Function
| -------------------------------------- | -------------------------------------------------------------
| `api/v2/tag_sets/single/<tag_sets_id>` | Return the tag set in which `tag_sets_id` equals `<tag_sets_id>`

#### Query Parameters

None.

#### Output description

| Field                 | Description
|-----------------------|-----------------------------------
| tags\_sets\_id        | Media Cloud internal ID of the tag set
| name                  | text of tag set, often cryptic
| label                 | a short human readable label for the tag
| description           | a couple of sentences describing the meaning of the tag
| show\_on\_media       | recommendation to show this tag as an option for searching solr using the tags_id_media
| show\_on\_stories     | recommendation to show this tag as an option for searching solr using the tags_id_stories


The show\_on\_media and show\_on\_stories fields are useful for picking out which tags are likely to be useful for
external researchers.  A tag should be considered useful for searching via tags\_id\_media or tags\_id\_stories
if show\_on\_media or show\_on\_stories, respectively, is set to true for _either_ the specific tag or its parent
tag set.

#### Example

Fetching information on the tag set 5.

URL: https://api.mediacloud.org/api/v2/tag_sets/single/5

Response:

```json
[
  {
    "tag_sets_id": 5,
    "show_on_stories": null,
    "name": "collection",
    "label": "Collections",
    "show_on_media": null,
    "description": "Curated collections of media sources.  This is our primary way of organizing our media sources -- almost every media source in our system is a member of one or more of these curated collections.  Some collections are manually curated, and others are generated using quantitative metrics."
    }
]
```

### api/v2/tag_sets/list/

| URL                     | Function
| ----------------------- | -----------------------------
| `api/v2/tag_sets/list`  | Return all `tag_sets`

#### Query Parameters

| Parameter          | Default | Notes
| ------------------ | ------- | -----------------------------------------------------------------
| `last_tag_sets_id` | 0       | Return tag sets with a `tag_sets_id` greater than this value
| `rows`             | 20      | Number of tag sets to return. Cannot be larger than 100

None.

#### Example

URL: https://api.mediacloud.org/api/v2/tag_sets/list

## Controversies

Controversies are collections of stories within some date range that match some pattern
indicating that they belong to some topic.  Controversies both stories matched from
crawled Media Cloud content and stories discovered by spidering out from the links of
those matched stories. For more information about controversies and how they are generated,
see:

http://cyber.law.harvard.edu/publications/2013/social_mobilization_and_the_networked_public_sphere

A single controversy is the umbrella object that represents the whole controversy.  A controversy dump
is a frozen version of the data within a controversy that keeps a consistent view of a controversy
for researchers and also includes analytical results like link counts.  A controversy time slice
represents the set of stories active in a controversy within a given date range.  Every controversy time
slice belongs to a controversy dump.

Controversy data can be used to search stories and media sources as well.  Use the
controversy_dump_time_slices_id param to list the media sources within a given controversy
time slice.  See the documentation for solr pseudo queries for documentation of how to
query for stories within a controversy.

### api/v2/controversies/single/

| URL                                                | Function
| -------------------------------------------------- | -------------------------------------------------------------
| `api/v2/controversies/single/<controversies_id>`   | Return a single controversy

#### Query Parameters

None.

#### Example

Fetching information on controversy 6.

URL: https://api.mediacloud.org/api/v2/controversies/single/6

Response:

```json
[
  {
    "controversies_id": 6,
    "controversy_tag_sets_id": 14,
    "description": "obama",
    "name": "obama",
    "media_type_tag_sets_id": 18
    "pattern": "[[:<:]]obama|obamacare[[:>:]]",
    "solr_seed_query": "obama OR obamacare",
    "solr_seed_query_run": 1,
  }
]
```

### api/v2/controversies/list/

| URL                          | Function
| ---------------------------- | -----------------------------
| `api/v2/controversies/list`  | Return controversies

#### Query Parameters

| Parameter       | Default    | Notes
| --------------- | ---------- | -----------------------------------------------------------------
| `name`          | null       | Search for controversies with names including the given text

#### Example

URL: https://api.mediacloud.org/api/v2/controversies/list

### api/v2/controversy_dumps/single/

| URL                                      | Function
| ---------------------------------------- | -------------------------------------------------------------
| `api/v2/controversy_dumps/single/<id>`   | Return a single controversy dump

#### Query Parameters

None.

#### Example

Fetching information on the controversy dump 5.

URL: https://api.mediacloud.org/api/v2/controversy_dumps/single/5

Response:

```json
[
  {
    "controversies_id": 6,
    "controversy_dumps_id": 5,
    "dump_date": "2014-07-30 16:32:15.479964",
    "end_date": "2015-01-01 00:00:00",
    "note": null
    "start_date": "2014-01-01 00:00:00",
  }
]
```

### api/v2/controversy_dumps/list/

| URL                              | Function
| -------------------------------- | ---------------------------------------------------
| `api/v2/controversy_dumps/list`  | Return controversy dumps sorted by descending date

#### Query Parameters

| Parameter          | Default    | Notes
| ------------------ | ---------- | -----------------------------------------------------------------
| `controversies_id` | null       | Return dumps within the given controversy

#### Example

URL: https://api.mediacloud.org/api/v2/controversy_dumps/list?controversies_id=6

### api/v2/controversy_dump_time_slices/single/

| URL                                                 | Function
| --------------------------------------------------- | -------------------------------------------------------------
| `api/v2/controversy_dump_time_slices/single/<id>`   | Return a single controversy dump time slice

#### Query Parameters

None.

#### Example

Fetching information on the controversy dump 5.

URL: https://api.mediacloud.org/api/v2/controversy_dumps/single/5

Response:

```json
[
  {
    "controversy_dumps_id": 5,
    "controversy_dump_time_slices_id": 145,
    "end_date": "2015-01-01 00:00:00",
    "include_undateable_stories": 0,
    "medium_count": 236,
    "medium_link_count": 266,
    "model_num_media": 17,
    "model_r2_mean": "0.96",
    "model_r2_stddev": "0",
    "period": "overall",
    "tags_id": null,
    "start_date": "2014-01-01 00:00:00"
    "story_count": 2148,
    "story_link_count": 731,
  }
]
```

### api/v2/controversy_dump_time_slices/list/

| URL                                         | Function
| ------------------------------------------- | ---------------------------------------------------
| `api/v2/controversy_dump_time_slices/list`  | Return controversy dump time slices

#### Query Parameters
# controversy_dumps_id tags_id period start_date end_date
| Parameter              | Default | Notes
| ---------------------- | ------- | -----------------------------------------------------------------
| `controversy_dumps_id` | null    | Return time slices within the dump
| `tags_id`              | null    | Return time slices associated with the tag
| `period`               | null    | Return time slices with the given period ('weekly', 'monthly', 'overall', or 'custom'
| `start_date`           | null    | Return time slices that start on the given date (YYYY-MM-DD)
| `end_date`             | null    | Return time slices that end on the given date (YYYY-MM-DD)

#### Example

URL: https://api.mediacloud.org/api/v2/controversy_dump_time_slices/list?controversies_dumps_id=5

# Extended Examples

Note: The Python examples below are included for reference purposes. However, a [Python client]( https://github.com/c4fcm/MediaCloud-API-Client ) for our API is now available and most Python users will find it much easier to use the API client instead of making web requests directly.

## Output Format / JSON

The format of the API responses is determined by the `Accept` header on the request. The default is `application/json`. Other supported formats include `text/html`, `text/x-json`, and `text/x-php-serialization`. It's recommended that you explicitly set the `Accept` header rather than relying on the default.

Here's an example of setting the `Accept` header in Python:

```python
import pkg_resources

import requests
assert pkg_resources.get_distribution("requests").version >= '1.2.3'

r = requests.get( 'https://api.mediacloud.org/api/v2/media/list', params = params, headers = { 'Accept': 'application/json'}, headers = { 'Accept': 'application/json'} )

data = r.json()
```

## Create a CSV file with all media sources.

```python
media = []
start = 0
rows  = 100
while True:
      params = { 'start': start, 'rows': rows, 'key': MY_KEY }
      print "start:{} rows:{}".format( start, rows)
      r = requests.get( 'https://api.mediacloud.org/api/v2/media/list', params = params, headers = { 'Accept': 'application/json'} )
      data = r.json()

      if len(data) == 0:
      	 break

      start += rows
      media.extend( data )

fieldnames = [
 u'media_id',
 u'url',
 u'moderated',
 u'moderation_notes',
 u'name'
 ]

with open( '/tmp/media.csv', 'wb') as csvfile:
    print "open"
    cwriter = csv.DictWriter( csvfile, fieldnames, extrasaction='ignore')
    cwriter.writeheader()
    cwriter.writerows( media )

```

## Grab all processed stories from US Mainstream Media as a stream

This is broken down into multiple steps for convenience and because that's probably how a real user would do it.

The you almost always want to search by a specific media source or media set.  The easiest way to find a relevant media
set is to use our [Sources Tool](https://sources.mediameter.org).  The url for a the US Mainstream Media  media set in
the sources tool looks like this:

https://sources.mediameter.org/#media-tag/8875027/details

The number in that url is the tags_id of the media set.

### Grab stories by querying stories_public/list

We can obtain all stories by repeatedly querying api/v2/stories_public/list using the `q` parameter to restrict to `tags_id_media=8875027` and changing the `last_processed_stories_id` parameter.

This is shown in the Python code below where `process_stories` is a user provided function to process this data.

```python
import requests

start = 0
rows  = 100
while True:
      params = { 'last_processed_stories_id': start, 'rows': rows, 'q': 'tags_id_media:8875027', 'key': MY_KEY }

      print "Fetching {} stories starting from {}".format( rows, start)
      r = requests.get( 'https://api.mediacloud.org/api/v2/stories_public/list/', params = params, headers = { 'Accept': 'application/json'} )
      stories = r.json()

      if len(stories) == 0:
      	 break

      start = stories[ -1 ][ 'processed_stories_id' ]

      process_stories( stories )
```


## Grab all stories in The New York Times during October 2012

### Find the `media_id` of The New York Times

Currently, the best way to do this is to create a CSV file with all media sources as shown in the earlier example.

Once you have this CSV file, manually search for The New York Times. You should find an entry for The New York Times at the top of the file with `media_id=1`.

### Grab stories by querying stories_public/list

We can obtain the desired stories by repeatedly querying `api/v2/stories_public/list` using the `q` parameter to restrict to `media_id` to 1 and  the `fq` parameter to restrict by date range. We repeatedly change the `last_processed_stories_id` parameter to obtain all stories.

This is shown in the Python code below where `process_stories` is a user provided function to process this data.

```python
import requests

start = 0
rows  = 100
while True:
      params = { 'last_processed_stories_id': start,
      'rows': rows, 'q': 'media_set_id:1', 'fq': 'publish_date:[2010-10-01T00:00:00Z TO 2010-11-01T00:00:00Z]', 'key': MY_KEY  }

      print "Fetching {} stories starting from {}".format( rows, start)
      r = requests.get( 'https://api.mediacloud.org/api/v2/stories_public/list/', params = params, headers = { 'Accept': 'application/json'} )
      stories = r.json()

      if len(stories) == 0:
      	 break

      start = stories[ -1 ][ 'processed_stories_id' ]

      process_stories( stories )
```

## Get word counts for top words for sentences matching 'trayvon' in US Mainstream Media during April 2012

### Find the media set

As above, find the tags_id of the US Mainstream Media set (8875027).

### Make a request for the word counts based on `tags_id_media`, sentence text and date range

One way to appropriately restrict the data is by setting the `q` parameter to restrict by sentence content and then the `fq` parameter twice to restrict by `tags_id_media` and `publish_date`.

Below `q` is set to `"sentence:trayvon"` and `fq` is set to `"tags_iud_media:8875027" and "publish_date:[2012-04-01T00:00:00.000Z TO 2013-05-01T00:00:00.000Z]"`. (Note that ":", "[", and "]" are URL encoded.)

```
curl 'https://api.mediacloud.org/api/v2/wc?q=sentence:trayvon&fq=tags_iud_media:8875027&fq=publish_date:%5B2012-04-01T00:00:00.000Z+TO+2013-05-01T00:00:00.000Z%5D'
```

Alternatively, we could use a single large query by setting `q` to `"sentence:trayvon AND tags_id_media:8875027 AND publish_date:[2012-04-01T00:00:00.000Z TO 2013-05-01T00:00:00.000Z]"`:

```
curl 'https://api.mediacloud.org/api/v2/wc?q=sentence:trayvon+AND+tags_id_media:8875027+AND+publish_date:%5B2012-04-01T00:00:00.000Z+TO+2013-05-01T00:00:00.000Z%5D&fq=tags_id_media:8875027&fq=publish_date:%5B2012-04-01T00:00:00.000Z+TO+2013-05-01T00:00:00.000Z%5D'
```


## Get word counts for top words for sentences with the tag `'odd'` in `tag_set = 'ts'`


###Find the `tag_sets_id` for `'ts'`

The user requests a list of all tag sets.

```
curl https://api.mediacloud.org/api/v2/tag_sets/list
```

```json
[
  {
    "tag_sets_id": 597,
    "name": "gv_country"
   },
   // additional tag sets skipped for space
  {
    "tag_sets_id": 800,
    "name": "ts"
   },

]
```

Looking through the output, the user sees that the `tag_sets_id` is 800.

###Find the `tags_id` for `'odd'` given the `tag_sets_id`

The following Python function shows how to find a `tags_id` given a `tag_sets_id`

```python
def find_tags_id( tag_name, tag_sets_id):
   last_tags_id = 0
   rows  = 100
   while True:
      params = { 'last_tags_id': last_tags_id, 'rows': rows, 'key': MY_KEY }
      print "start:{} rows:{}".format( start, rows)
      r = requests.get( 'https://api.mediacloud.org/api/v2/tags/list/' + tag_sets_id , params = params, headers = { 'Accept': 'application/json'} )
      tags = r.json()

      if len(tags) == 0:
         break

      for tag in tags:
          if tag['tag'] == tag_name:
             return tag['tags_id']

          last_tags_id = max( tag[ 'tags_id' ], last_tags_id )

   return -1

```

###Request a word count using the `tags_id`

Assume that the user determined that the `tags_id` was 12345678 using the above code.  The following will return
the word count for all sentences in stories belonging to any media source associated with tag 12345678.

```
curl 'https://api.mediacloud.org/api/v2/wc?q=tags_id_media:12345678'
```

## Grab stories from 10 January 2014 with the tag `'foo:bar'`

### Find the `tag_sets_id` for `'foo'`

See the "Get Word Counts for Top Words for Sentences with the Tag `'odd'` in `tag_set = 'ts'`" example above.

### Find the `tags_id` for `'bar'` given the `tag_sets_id`

See the "Get Word Counts for Top Words for Sentences with the Tag `'odd'` in `tag_set = 'ts'`" example above.

### Grab stories by querying stories_public/list

We assume the `tags_id` is 678910.

```
import requests

start = 0
rows  = 100
while True:
      params = { 'last_processed_stories_id': start, 'rows': rows, 'q': 'tags_id_stories:678910', 'key': MY_KEY }

      print "Fetching {} stories starting from {}".format( rows, start)
      r = requests.get( 'https://api.mediacloud.org/api/v2/stories_public/list/', params = params, headers = { 'Accept': 'application/json'} )
      stories = r.json()

      if len(stories) == 0:
         break

      start = stories[ -1 ][ 'processed_stories_id' ]

      process_stories( stories )
```
