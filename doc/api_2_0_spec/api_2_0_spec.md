<!-- MEDIACLOUD-TOC-START -->

Table of Contents
=================

   * [Overview](#overview)
      * [Authentication](#authentication)
         * [Example](#example)
      * [Python Client](#python-client)
      * [API URLs](#api-urls)
      * [Supported Languages](#supported-languages)
      * [Errors](#errors)
      * [Request Limits](#request-limits)
   * [Media](#media)
      * [api/v2/media/single/](#apiv2mediasingle)
         * [Query Parameters](#query-parameters)
         * [Example](#example-1)
      * [api/v2/media/list/](#apiv2medialist)
         * [Query Parameters](#query-parameters-1)
      * [api/v2/media/submit_suggestion - POST](#apiv2mediasubmit_suggestion---post)
         * [Input Description](#input-description)
         * [Example](#example-2)
   * [Media Health](#media-health)
      * [api/v2/mediahealth/list](#apiv2mediahealthlist)
         * [Query Parameters](#query-parameters-2)
         * [Output description](#output-description)
         * [Example](#example-3)
   * [Feeds](#feeds)
      * [api/v2/feeds/single](#apiv2feedssingle)
         * [Query Parameters](#query-parameters-3)
         * [Example](#example-4)
      * [api/v2/feeds/list](#apiv2feedslist)
         * [Query Parameters](#query-parameters-4)
         * [Example](#example-5)
   * [Stories](#stories)
      * [Output description](#output-description-1)
      * [api/v2/stories_public/single](#apiv2stories_publicsingle)
         * [Example](#example-6)
      * [api/v2/stories_public/list](#apiv2stories_publiclist)
         * [Query Parameters](#query-parameters-5)
         * [Example](#example-7)
      * [api/v2/stories_public/count](#apiv2stories_publiccount)
         * [Query Parameters](#query-parameters-6)
         * [Example](#example-8)
      * [api/v2/stories_public/tag_count](#apiv2stories_publictag_count)
         * [Query Parameters](#query-parameters-7)
         * [Example](#example-9)
      * [api/v2/stories_public/word_matrix](#apiv2stories_publicword_matrix)
         * [Query Parameters](#query-parameters-8)
         * [Output Description](#output-description-2)
   * [Sentences](#sentences)
      * [api/v2/sentences/count](#apiv2sentencescount)
      * [api/v2/sentences/field_count](#apiv2sentencesfield_count)
   * [Word Counting](#word-counting)
      * [api/v2/wc/list](#apiv2wclist)
         * [Query Parameters](#query-parameters-9)
         * [Example](#example-10)
   * [Tags and Tag Sets](#tags-and-tag-sets)
      * [api/v2/tags/single/](#apiv2tagssingle)
         * [Query Parameters](#query-parameters-10)
         * [Output description](#output-description-3)
         * [Example](#example-11)
      * [api/v2/tags/list/](#apiv2tagslist)
         * [Query Parameters](#query-parameters-11)
         * [Example](#example-12)
      * [api/v2/tag_sets/single/](#apiv2tag_setssingle)
         * [Query Parameters](#query-parameters-12)
         * [Output description](#output-description-4)
         * [Example](#example-13)
      * [api/v2/tag_sets/list/](#apiv2tag_setslist)
         * [Query Parameters](#query-parameters-13)
         * [Example](#example-14)
   * [Registration and Authentication](#registration-and-authentication)
      * [Register](#register)
         * [api/v2/auth/register (POST)](#apiv2authregister-post)
            * [Required role](#required-role)
            * [Input Description](#input-description-1)
            * [Output Description](#output-description-5)
               * [Registration was successful](#registration-was-successful)
               * [Registration has failed](#registration-has-failed)
            * [Example](#example-15)
         * [api/v2/auth/activate (POST)](#apiv2authactivate-post)
            * [Required role](#required-role-1)
            * [Input Description](#input-description-2)
            * [Output Description](#output-description-6)
               * [Activating the user was successful](#activating-the-user-was-successful)
               * [Activating the user has failed](#activating-the-user-has-failed)
            * [Example](#example-16)
         * [api/v2/auth/resend_activation_link (POST)](#apiv2authresend_activation_link-post)
            * [Required role](#required-role-2)
            * [Input Description](#input-description-3)
            * [Output Description](#output-description-7)
               * [Resending the activation email was successful](#resending-the-activation-email-was-successful)
               * [Resending the activation email has failed](#resending-the-activation-email-has-failed)
            * [Example](#example-17)
      * [Reset password](#reset-password)
         * [api/v2/auth/send_password_reset_link (POST)](#apiv2authsend_password_reset_link-post)
            * [Required role](#required-role-3)
            * [Input Description](#input-description-4)
            * [Output Description](#output-description-8)
               * [Sending the password reset link was successful](#sending-the-password-reset-link-was-successful)
               * [Sending the password reset link has failed](#sending-the-password-reset-link-has-failed)
            * [Example](#example-18)
         * [api/v2/auth/reset_password (POST)](#apiv2authreset_password-post)
            * [Required role](#required-role-4)
            * [Input Description](#input-description-5)
            * [Output Description](#output-description-9)
               * [Resetting the user's password was successful](#resetting-the-users-password-was-successful)
               * [Resetting the user's password has failed](#resetting-the-users-password-has-failed)
            * [Example](#example-19)
      * [Log in](#log-in)
         * [api/v2/auth/login (POST)](#apiv2authlogin-post)
            * [Required role](#required-role-5)
            * [Input Description](#input-description-6)
            * [Output Description](#output-description-10)
               * [User was found](#user-was-found)
               * [User was not found](#user-was-not-found)
            * [Example](#example-20)
      * [User Profile](#user-profile)
         * [api/v2/auth/profile (GET)](#apiv2authprofile-get)
            * [Required role](#required-role-6)
            * [Output Description](#output-description-11)
            * [Example](#example-21)
         * [api/v2/auth/change_password (POST)](#apiv2authchange_password-post)
            * [Required role](#required-role-7)
            * [Input Description](#input-description-7)
            * [Output Description](#output-description-12)
               * [Changing the user's password was successful](#changing-the-users-password-was-successful)
               * [Changing the user's password has failed](#changing-the-users-password-has-failed)
            * [Example](#example-22)
         * [api/v2/auth/reset_api_key (POST)](#apiv2authreset_api_key-post)
            * [Required role](#required-role-8)
            * [Output Description](#output-description-13)
               * [Resetting user's API key was successful](#resetting-users-api-key-was-successful)
               * [Resetting user's API key has failed](#resetting-users-api-key-has-failed)
            * [Example](#example-23)
   * [Stats](#stats)
      * [api/v2/stats/list](#apiv2statslist)
         * [Query Parameters](#query-parameters-14)
         * [Output Description](#output-description-14)
         * [Example](#example-24)
   * [Util](#util)
      * [api/v2/util/is_syndicated_ap (POST)](#apiv2utilis_syndicated_ap-post)
         * [Input Description](#input-description-8)
         * [Output Description](#output-description-15)
         * [Example](#example-25)
   * [Extended Examples](#extended-examples)
      * [Output Format / JSON](#output-format--json)
      * [Create a CSV file with all media sources.](#create-a-csv-file-with-all-media-sources)
      * [Grab all processed stories from US Mainstream Media as a stream](#grab-all-processed-stories-from-us-mainstream-media-as-a-stream)
      * [Grab stories by querying stories_public/list](#grab-stories-by-querying-stories_publiclist)
      * [Grab all stories in The New York Times during October 2012](#grab-all-stories-in-the-new-york-times-during-october-2012)
         * [Find the media_id of The New York Times](#find-the-media_id-of-the-new-york-times)
         * [Grab stories by querying stories_public/list](#grab-stories-by-querying-stories_publiclist-1)
      * [Get word counts for top words for sentences matching 'trayvon' in US Mainstream Media during April 2012](#get-word-counts-for-top-words-for-sentences-matching-trayvon-in-us-mainstream-media-during-april-2012)
         * [Find the media collection](#find-the-media-collection)
         * [Make a request for the word counts based on tags_id_media, sentence text and date range](#make-a-request-for-the-word-counts-based-on-tags_id_media-sentence-text-and-date-range)
      * [Get word counts for top words for sentences with the tag 'odd' in <code>tag_set = 'ts'</code>](#get-word-counts-for-top-words-for-sentences-with-the-tag-odd-in-tag_set--ts)
         * [Find the tag_sets_id for <code>'ts'</code>](#find-the-tag_sets_id-for-ts)
      * [Find the tags_id for <code>'odd'</code> given the <code>tag_sets_id</code>](#find-the-tags_id-for-odd-given-the-tag_sets_id)
         * [Request a word count using the tags_id](#request-a-word-count-using-the-tags_id)
      * [Grab stories from 10 January 2014 with the tag 'foo:bar'](#grab-stories-from-10-january-2014-with-the-tag-foobar)
         * [Find the tag_sets_id for <code>'foo'</code>](#find-the-tag_sets_id-for-foo)
         * [Find the tags_id for <code>'bar'</code> given the <code>tag_sets_id</code>](#find-the-tags_id-for-bar-given-the-tag_sets_id)
      * [Grab stories by querying stories_public/list](#grab-stories-by-querying-stories_publiclist-2)

----
<!-- MEDIACLOUD-TOC-END -->


# Overview

## Authentication

Every call below includes a `key` parameter which will authenticate the user to the API service.  The key parameter is excluded from the examples in the below sections for brevity.

To get a key, register for a user:

https://topics.mediacloud.org/#/user/signup

Once you have an account go here to see your key:

https://topics.mediacloud.org/#/user/profile

### Example

https://api.mediacloud.org/api/v2/media/single/1?key=KRN4T5JGJ2A

## Python Client

A [Python client]( https://github.com/c4fcm/MediaCloud-API-Client ) for our API is now available. Users who develop in
Python will probably find it easier to use this client than to make web requests directly. The Python client is
available [here]( https://github.com/c4fcm/MediaCloud-API-Client ).

## API URLs

*Note:* by default the API only returns a subset of the available fields in returned objects. The returned fields are those that we consider to be the most relevant to users of the API. If the `all_fields` parameter is provided and is non-zero, then a more complete list of fields will be returned. For space reasons, we do not list the `all_fields` parameter on individual API descriptions.

## Supported Languages

The following language are supported (by 2 letter language code):

* `ca` (Catalan)
* `da` (Danish)
* `de` (German)
* `en` (English)
* `es` (Spanish)
* `fi` (Finnish)
* `fr` (French)
* `ha` (Hausa)
* `hi` (Hindi)
* `hu` (Hungarian)
* `it` (Italian)
* `ja` (Japanese)
* `lt` (Lithuanian)
* `nl` (Dutch)
* `no` (Norwegian)
* `pt` (Portuguese)
* `ro` (Romanian)
* `ru` (Russian)
* `sv` (Swedish)
* `tr` (Turkish)
* `zh` (Chinese)

## Errors

The Media Cloud returns an appropriate HTTP status code for any error, along with a JSON document in the following format:

```json
{ "error": "error message" }
```

## Request Limits

Each user is limited to 1,000 API calls and 20,000 stories returned in any 7 day period.  Requests submitted beyond this
limit will result in a status 403 error.  Users who need access to more requests should email info@mediacloud.org.


# Media

The Media API calls provide information about media sources.  A media source is a publisher of content, such as the New York
Times or Instapundit.  Every story belongs to a single media source.  Each media source can have zero or more feeds.

## api/v2/media/single/

| URL                              | Function
| -------------------------------- | -------------------------------------------------------------
| `api/v2/media/single/<media_id>` | Return the media source in which `media_id` equals `<media_id>`

### Query Parameters

None.

### Example

Fetching information on The New York Times

URL: https://api.mediacloud.org/api/v2/media/single/1

Response:

```json
[
    {
        "url": "http://nytimes.com",
        "name": "New York Times",
        "media_id": 1,
        "is_healthy": 1,
        "is_monitored": 1,
        "public_notes": "all the news that's fit to print",
        "editor_nnotes": "first media source",
        "num_stories_90": 123,
        "num_sentences_90": 1234,
        "start_date": "2016-01-01",
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
        "activities": [
            {
                "date": "2015-08-12 18:17:35.922523",
                "field": "name",
                "new_value": "New York Times",
                "old_value": "nytimes.com"
            }
        ]
    }
]
```

## api/v2/media/list/

| URL                 | Function
| ------------------- | -----------------------------
| `api/v2/media/list` | Return multiple media sources

### Query Parameters

| Parameter          | Default | Notes
| ------------------ | ------- | -----------------------------------------------------------------
| `last_media_id`    | 0       | Return media sources with a `media_id` greater than this value
| `rows`             | 20      | Number of media sources to return. Cannot be larger than 100
| `name`             | none    | Name of media source for which to search
| `tag_name`         | none    | Name of tag for which to return belonging media
| `timespans_id`     | null    | Return media within the given timespan
| `topic_mode`       | null    | If set to 'live', return media from live topics
| `tags_id`          | null    | Return media associated with any of the given tags
| `q`                | null    | Return media with at least one sentence that matches the Solr query
| `include_dups`     | 0       | Include duplicate media among the results
| `unhealthy` | none | Only return media that are currently marked as unhealthy (see mediahealth/list)
| `similar_media_id` | none | Return media with the most tags in common
|  `sort`            | id   | sort order of media: `id`, or `num_stories` |

If the name parameter is specified, the call returns only media sources that match a case insensitive search specified value.  If the specified value is less than 3 characters long, the call returns an empty list.

By default, media are sorted by media_id.  If the sort parameter is set to 'num_stories', the media will be sorted
by decreasing number of stories in the past 90 days.

By default, calls that specify a name parameter will only return media that are not duplicates of
some other media source.  Media Cloud has many media sources that are either subsets of other media sources or are
just holders for spidered media from a given media source, both of which are marked as duplicate media and are not
included in the default results.  If the 'include_dups' parameter is set to 1, those duplicate sources will be
included in the results.

If the `timespans_id` parameter is specified, return media within the given time slice,
sorted by descending inlink_count within the timespan.  If `topic_mode` is set to
'live', return media from the live topic stories rather than from the frozen snapshot.

If the `q` parameter is specified, return only media that include at least on sentence that matches the given Solr query.  For a description of the Solr query format, see the `stories_public/list` call.

All tags specified in the `tags\_id` parameter are OR'd together.  Additonal lists of tags can be specified in
numbered tags_id lists, eg. `tags\_id\_1`. Each set of numbered tag lists will be AND'd together.

URL: https://api.mediacloud.org/api/v2/media/list?last_media_id=1&rows=2

Output format is the same as for api/v2/media/single above.

## api/v2/media/submit_suggestion - POST

| URL                 | Function
| ------------------- | -----------------------------
| `api/v2/media/submit_suggestion` | Suggest a media source for Media Cloud to crawl

This API end point allows the user to send a suggest a new media source to the Media Cloud team for regular crawling.

### Input Description

| Field | Description |
|------|------------ |
| url | URL of the media source home page (required) |
| name | Human readable name of media source (optional) |
| feed_url | URL of RSS, RDF, or Atom syndication feed for the source (optional) |
| reason | Reason media source should be added to the system (optional) |
| tags_ids |  list of suggested tags to add to the source (optional ) |

### Example

URL: https://api.mediacloud.org/api/v2/media/submit_suggestion

Input:
```json
{
    "name": "Cameroon Tribue",
    "url": "http://www.cameroon-tribune.cm"
}
```

Output:

```json
{ "success": 1 }
```

# Media Health

The Media Health API call provides information about the health of a media source, meaning to what degree we are
capturing all of the stories published by that media source.  Media Cloud collects its data via
automatically detected RSS feeds on the open web.  This means first that the system generally has data for a given
media source from the time we first enter that source into our database.  Second, Media Cloud data for a given media
source is only as good as the set of feeds we have for that source.  Our feed scraper is not perfect and so sometimes
misses feeds it should be collecting.   Third, feeds change over time.  We periodically rescrape every media source
for new feeds, but this takes time and is not perfect.

The only way we have of judging the health is judging the relative number of stories over time.  This media call
provides a set of metrics that compare the current number of stories being collected by the media source with
the number of stories collected over the past 90 days, and also compares coverage over time with the expected
volume.  More details are in the field descriptions below

## api/v2/mediahealth/list

| URL                              | Function
| -------------------------------- | -------------------------------------------------------------
| `api/v2/mediahealth/list`        | Return media health data for the given media sources

### Query Parameters

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

### Example

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
        ]
    }
]
```



# Feeds

A feed could be one of the following types:

* **`syndicated` feed** - a RSS / Atom feed. Each time a `syndicated` feed is downloaded, each new URL found in the feed is
added to the feed's media source as a story.
* **`web_page` feed** - homepage of the main website. Each time a web page feed is downloaded, that web page itself is added as a story for the feed's media source.
* **`univision` feed** - a special format feed for collecting Univision.com's data.
* **`ap` feed** - a special format feed for collecting Associated Press data.
* **`podcast` feed** - a RSS / Atom feed the enclosure of which is treated as a podcast episode and gets transcribed to text.

Each feed is downloaded between once an hour and once a day depending on traffic.

Each feed belongs to a single media source. Each story can belong to one or more feeds from the same media source.

## api/v2/feeds/single

| URL                              | Function
| -------------------------------- | --------------------------------------------------------
| `api/v2/feeds/single/<feeds_id>` | Return the feed for which `feeds_id` equals `<feeds_id>`

### Query Parameters

None.

### Example

URL: https://api.mediacloud.org/api/v2/feeds/single/1

```json
[
    {
        "name": "Bits",
        "url": "http://bits.blogs.nytimes.com/rss2.xml",
        "feeds_id": 1,
        "type": "syndicated",
        "media_id": 1
    }
]
```

## api/v2/feeds/list

| URL                 | Function
| ------------------- | --------------------------
| `api/v2/feeds/list` | Return multiple feeds

### Query Parameters

| Parameter            | Default    | Notes
| -------------------- | ---------- | -----------------------------------------------------------------
| `last_feeds_id`      | 0          | Return feeds in which `feeds_id` is greater than this value
| `rows`               | 20         | Number of feeds to return. Cannot be larger than 100
| `media_id`           | (required) | Return feeds belonging to the media source

### Example

URL: https://api.mediacloud.org/api/v2/feeds/list?media_id=1

Output format is the same as for api/v2/feeds/single above.

# Stories

A story represents a single published piece of content.  Each unique URL downloaded from any syndicated feed within
a single media source is represented by a single story.  For example, a single New York Times newspaper story is a
Media Cloud story, as is a single Instapundit blog post.  Only one story may exist for a given title for each 24 hours
within a single media source.

## Output description

The following table describes the meaning and origin of fields returned by both api/v2/stories_public/single and api/v2/stories_public/list.

| Field               | Description
| ------------------- | ----------------------------------------------------------------------
| `stories_id`        | The internal Media Cloud ID for the story.
| `media_id`          | The internal Media Cloud ID for the media source to which the story belongs.
| `media_name`        | The name of the media source to which the story belongs.
| `media_url`         | The URL of the media source to which the story belongs.
| `publish_date`      | The publish date of the story as specified in the RSS feed.
| `tags`              | A list of any tags associated with this story, including those written through the write-back api.
| `collect_date`      | The date the RSS feed was actually downloaded.
| `url`               | The URL field in the RSS feed.
| `guid`              | The GUID field in the RSS feed. Defaults to the URL if no GUID is specified in the RSS feed.
| `language`          | The language of the story as detected by the chromium compact language detector library.
| `title`             | The title of the story as found in the RSS feed.
| `ap_syndicated`     | Whether our detection algorithm thinks that this is an English language syndicated AP story


## api/v2/stories_public/single

| URL                                  | Function
| ------------------------------------ | ------------------------------------------------------
| `api/v2/stories_public/single/<stories_id>` | Return the story for which `stories_id` equals `<stories_id>`

### Example

Note: This fetches data on the CC licensed Global Voices story ["Myanmar's new flag and new name"](http://globalvoicesonline.org/2010/10/26/myanmars-new-flag-and-new-name/#comment-1733161) from November 2010.

URL: https://api.mediacloud.org/api/v2/stories_public/single/27456565


```json
[
    {
        "collect_date": "2010-11-24 15:33:39",
        "url": "http://globalvoicesonline.org/2010/10/26/myanmars-new-flag-and-new-name/comment-page-1/#comment-1733161",
        "guid": "http://globalvoicesonline.org/?p=169660#comment-1733161",
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "media_name": "Global Voices Online",
        "media_url": "http://globalvoicesonline.org/",
        "stories_id": 27456565,
        "story_tags": [ 1234235 ],
    }
]
```

## api/v2/stories_public/list

| URL                             | Function
| ------------------------------- | ---------------------------------
| `api/v2/stories_public/list` | Return multiple processed stories

### Query Parameters

| Parameter                    | Default                | Notes |
| ---------------------------- | ---------------------- | ------------------------------------------------------------------------------|
| `last_processed_stories_id`  | 0  | Return stories in which the `processed_stories_id` is greater than this value. |
| `rows`                       | 20                     | Number of stories to return, max 1000. |
| `feeds_id` | null | Return only stories that match the given feeds_id, sorted my descending publish date |
| `q`  | null  | If specified, return only results that match the given Solr query.  Only one `q` parameter may be included. |
| `fq`             | null    | If specified, file results by the given Solr query.  More than one `fq` parameter may be included. |
| `sort`                       | `processed_stories_id` | Returned results sort order. Supported values: processed_stories_id, random |
| `wc` | 0 | if set to 1, include a 'word_count' field with each story that includes a count of the most common words in the story |
| `show_feeds` | if set to 1, include a 'feeds' field with a list of the feeds associated with this story |


The `last_processed_stories_id` parameter can be used to page through these results. The API will return stories with a`processed_stories_id` greater than this value.  To get a continuous stream of stories as they are processed by Media Cloud, the user must make a series of calls to api/v2/stories_public/list in which `last_processed_stories_id` for each
call is set to the `processed_stories_id` of the last story in the previous call to the API.  A single call can only
return up to 10,000 results, but you can get the full list of results by paging through the full list using
`last_processed_stories_id`.

*Note:* `stories_id` and `processed_stories_id` are separate values. The order in which stories are processed is different than the `stories_id` order. The processing pipeline involves downloading, extracting, and vectoring stories. Requesting by the `processed_stories_id` field guarantees that the user will receive every story (matching the query criteria if present) in
the order it is processed by the system.

The `q` and `fq` parameters specify queries to be sent to a Solr server that indexes all Media Cloud stories.  The Solr
server provides full text search indexing of each sentence collected by Media Cloud.  All content is stored as individual
sentences.  The api/v2/stories_public/list call searches for sentences matching the `q` and / or `fq` parameters if specified and
the stories that include at least one sentence returned by the specified query.

The `q` and `fq` parameters are passed directly through to Solr.  Documentation of the format of the `q` and `fq` parameters is [here](https://mediacloud.org/support/query-guide/).  

Below are the fields that may be used as Solr query parameters, for example 'text:obama AND media_id:1':

| Field                        | Description
| -------------------- | -----------------------------------------------------
| sentence             | the text of the sentence
| stories_id           | a story ID
| media_id             | the Media Cloud media source ID of a story
| publish_date         | the publish date of a story
| tags_id_story        | the ID of a tag associated with a story
| tags_id_media        | the ID of a tag associated with a media source
| processed_stories_id | the processed_stories_id as returned by stories_public/list

Be aware that ':' is usually replaced with '%3A' in programmatically generated URLs.

Solr range queries may only be used within the fq parameter.  Using a range query in the main q query will result in
an error.

### Example

The output of these calls is in exactly the same format as for the api/v2/stories_public/single call.

URL: https://api.mediacloud.org/api/v2/stories_public/list?last_processed_stories_id=8625915

Return a stream of all stories processed by Media Cloud, greater than the `last_processed_stories_id`.

URL: https://api.mediacloud.org/api/v2/stories_public/list?last_processed_stories_id=2523432&q=text:obama+AND+media_id:1

Return a stream of all stories from The New York Times mentioning `'obama'` greater than the given `last_processed_stories_id`.

## api/v2/stories_public/count

### Query Parameters

| Parameter          | Default          | Notes
| ------------------ | ---------------- | ----------------------------------------------------------------
| `q`                | n/a              | `q` ("query") parameter which is passed directly to Solr
| `fq`               | `null`           | `fq` ("filter query") parameter which is passed directly to Solr
| `split`            | `null`           | if set to 1 or true, split the counts into date ranges
| `split_period`     | `day`            | return counts for these date periods: day, week, month, year

The q and fq parameters are passed directly through to Solr (see description of q and fq parameters in api/v2/stories_public/list section above).

The call returns the number of stories returned by Solr for the specified query.

If split is specified, split the counts into periods set by split_period.


### Example

Count stories containing the word 'obama' in The New York Times.

URL: https://api.mediacloud.org/api/v2/stories_public/count?q=obama&fq=media_id:1

```json
{
    "count": 6620
}
```

Count stories containing 'africa' in the New York Times for each week from 2014-01-01 to 2014-03-01:

URL: https://api.mediacloud.org/api/v2/stories_public/count?split=1&split_period=week&q=africa%20AND%20media_id%3A1%20AND%20publish_day%3A%5B2014-01-01T00%3A00%3A00Z%20TO%202014-03-01T00%3A00%3A00Z%5D

```json
{
  "counts": [
    {
      "count": 25,
      "date": "2013-12-30 00:00:00"
    },
    {
      "count": 59,
      "date": "2014-01-06 00:00:00"
    },
    {
      "count": 70,
      "date": "2014-01-13 00:00:00"
    },
    {
      "count": 71,
      "date": "2014-01-20 00:00:00"
    },
    {
      "count": 80,
      "date": "2014-01-27 00:00:00"
    },
    {
      "count": 57,
      "date": "2014-02-03 00:00:00"
    },
    {
      "count": 54,
      "date": "2014-02-10 00:00:00"
    },
    {
      "count": 45,
      "date": "2014-02-17 00:00:00"
    },
    {
      "count": 44,
      "date": "2014-02-24 00:00:00"
    }
  ]
}
```

## api/v2/stories_public/tag_count

### Query Parameters

| Parameter          | Default          | Notes
| ------------------ | ---------------- | ----------------------------------------------------------------
| `q`                | n/a              | `q` ("query") parameter which is passed directly to Solr
| `fq`               | `null`           | `fq` ("filter query") parameter which is passed directly to Solr
| `limit`            | 1000             | number of tags to fetch from Solr
| `tag_sets_id`      | `null`           | return only tags belonging to this tag set

The q and fq parameters are passed directly through to Solr (see description of q and fq parameters in api/v2/stories_public/list section above).

The call returns list of the tags most commonly associated with stories that match the given query.  The limit parameter
s applied before the tag_sets_id parameter, so fewer than limit (or zero) results may be returned for a given tag set even if tags from that tag set are associated with stories matching the query.

### Example

Count tags in stories containing the word 'obama' in The New York Times.

URL: https://api.mediacloud.org/api/v2/stories_public/tag_count?q=obama&fq=media_id:1&limit=3

```json
[
 {
    "count": 20240,
    "description": "politics and government",
    "is_static": false,
    "label": "politics and government",
    "show_on_media": null,
    "show_on_stories": null,
    "tag": "politics and government",
    "tag_set_label": "nyt_labels",
    "tag_set_name": "nyt_labels",
    "tag_sets_id": 1963,
    "tags_id": 9360836
  },
  {
    "count": 17491,
    "description": "Obama",
    "is_static": false,
    "label": "Obama",
    "show_on_media": null,
    "show_on_stories": null,
    "tag": "Obama",
    "tag_set_label": "cliff_people",
    "tag_set_name": "cliff_people",
    "tag_sets_id": 2389,
    "tags_id": 9362721
  },
  {
    "count": 15904,
    "description": "united states politics and government",
    "is_static": false,
    "label": "united states politics and government",
    "show_on_media": null,
    "show_on_stories": null,
    "tag": "united states politics and government",
    "tag_set_label": "nyt_labels",
    "tag_set_name": "nyt_labels",
    "tag_sets_id": 1963,
    "tags_id": 9360846
  } 
]
```

## api/v2/stories_public/word_matrix

### Query Parameters

| Parameter          | Default          | Notes
| ------------------ | ---------------- | ----------------------------------------------------------------
| `q`                | n/a              | `q` ("query") parameter which is passed directly to Solr
| `fq`               | `null`           | `fq` ("filter query") parameter which is passed directly to Solr
| `rows`             | 1000             | number of stories to return from solr, max 100,000
| `max_words`        | n/a              | max number of non-zero count word stems to return for each story
| `stopword_length`  | n/a              | if set to 'tiny', 'short', or 'long', eliminate stop word list of that length

The q and fq parameters are passed directly through to Solr (see description of q and fq parameters in
api/v2/stories_public/list section above).

If stopword_length is specified, eliminate the 'tiny', 'short', or 'long' list of stopwords from the results, if the
system has stopwords for the language of each story. See [Supported Languages](#supported-languages) for a list of supported languages and their codes.

### Output Description

| Field                        | Description
| ---------------------------- | -----------------------------------------------------------------------------
| word_matrix                  | a dictionary of stories_ids, each pointing to a dictionary of word counts
| word_list                    | the list of word stems counted, in the order of the index used for the word counts


The word_matrix is a dictionary with the stories_id as the key and the word count dictionary of as
the value.  For each word count dictionary, the key is the word index of the word in the word_list and the
value is the count of the word in that story.


The word list is a list of lists.  The overall list includes the stems in the order that is referenced by the
word index in the word_matrix word count dictionary for each story.  Each individual list member includes the stem
counted and the most common full word used with that stem in the set.  

For the following two stories:

story id 1: 'foo bar bars'
story id 2: 'foo bars foos foo'

the returned data would look like:

```json
{
    "word_matrix": {
        "1": {
            "0": 1,
            "1": 2
        },
        "2": {
            "0": 3,
            "1": 1
        }
    },
    "word_list": [
        ["foo", "foo"],
        ["bar", "bars"]
    ]
}
```

# Sentences

The text of every story processed by Media Cloud is parsed into individual sentences.  Duplicate sentences within
the same media source in the same week are dropped (the large majority of those duplicate sentences are
navigational snippets wrongly included in the extracted text by the extractor algorithm).


## api/v2/sentences/count

This call has been removed.  Consider using `api/v2/stories_public/count` instead.

## api/v2/sentences/field\_count

This call has been removed.  Consider using `api/v2/stories_public/tag_count` instead.

# Word Counting

## api/v2/wc/list

Returns word frequency counts of the most common words in a randomly sampled set of all sentences returned by querying Solr using the `q` and `fq` parameters, with stopwords removed by default.  Words are stemmed before being counted.  For each word, the call returns the stem and the full term most used with the given stem in the specified Solr query (for example, in the below example, 'democrat' is the stem that appeared 58 times and 'democrats' is the word that was most commonly stemmed into 'democract').

### Query Parameters

| Parameter           | Default | Notes
| ------------------- | ------- | ----------------------------------------------------------------
| `q`                 | n/a     | `q` ("query") parameter which is passed directly to Solr
| `fq`                | `null`  | `fq` ("filter query") parameter which is passed directly to Solr
| `num_words`         | 500     | Number of words to return
| `sample_size`       | 1000    | Number of sentences to sample, max 100,000
| `random_seed`       | 1       | Seed value to use when generating random sample
| `include_stopwords` | 0       | Set to 1 to disable stopword removal
| `include_stats`     | 0       | Set to 1 to include stats about the request as a whole (such as total number of words)

See above `/api/v2/stories_public/list` for Solr query syntax.

To provide quick results, the API counts words in a randomly sampled set of sentences returned by the given query.  By default, the request will sample 1000 sentences and return 500 words.  You can make the API sample more sentences.  The system takes about one second to process each multiple of 1000 sentences.

Sentences are going to be tokenized into words by identifying each of the sentence's language and using this language's sentence splitting algorithm. Additionally, both English and the identified language's stopwords are going to be removed from results. See [Supported Languages](#supported-languages) for a list of supported languages and their codes.

Setting the 'stats' field to true changes the structure of the response, as shown in the example below. Following fields are included in the stats response:

| Field                    | Description
| ------------------------ | -------------------------------------------------------------------
| `num_words_returned`     | The number of words returned by the call, up to `num_words`
| `num_sentences_returned` | The number of sentences returned by the call, up to `sample_size`
| `num_sentences_found`    | The total number of sentences found by Solr to match the query
| `num_words_param`        | The `num_words` param passed into the call, or the default value
| `sample_size_param`      | The sample size passed into the call, or the default value

### Example

Get word frequency counts for all sentences containing the word `'obama'` in The New York Times

URL: <https://api.mediacloud.org/api/v2/wc/list?q=obama+AND+media_id:1>

```json
[
    {
        "count": 1014,
        "stem": "obama",
        "term": "obama"
    },
    {
        "count": 106,
        "stem": "republican",
        "term": "republican"
    },
    {
        "count": 78,
        "stem": "campaign",
        "term": "campaign"
    },
    {
        "count": 72,
        "stem": "romney",
        "term": "romney"
    },
    {
        "count": 59,
        "stem": "washington",
        "term": "washington"
    },
    {
        "count": 58,
        "stem": "democrat",
        "term": "democrats"
    }
]
```

Get word frequency counts for all sentences containing the word `'obama'` in The New York Times, with
stats data included

URL: <https://api.mediacloud.org/api/v2/wc/list?q=obama+AND+media_id:1&stats=1>

```json

{
    "stats": {
        "num_words_returned": 5123,
        "num_sentences_returned": 899,
        "num_sentences_found": 899
    },
    "words": [
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

# Tags and Tag Sets

Media Cloud associates tags with media sources, stories, and individual sentences.  A tag consists of a short snippet of text,
a `tags_id`, and `tag_sets_id`.  Each tag belongs to a single tag set.  The tag set provides a separate name space for a group
of related tags.  Each tag has a unique name ('tag') within its tag set.  Each tag set consists of a tag_sets_id and a uniaue
name.

For example, the `'gv_country'` tag set includes the tags `japan`, `brazil`, `haiti` and so on.  Each of these tags is associated with
some number of media sources (indicating that the given media source has been cited in a story tagged with the given country
in a Global Voices post).

## api/v2/tags/single/

| URL                              | Function
| -------------------------------- | -------------------------------------------------------------
| `api/v2/tags/single/<tags_id>`   | Return the tag in which `tags_id` equals `<tags_id>`

### Query Parameters

None.

### Output description

| Field                 | Description
|-----------------------|-----------------------------------
| tags_id               | Media Cloud internal tag ID
| tags\_sets\_id        | Media Cloud internal ID of the parent tag set
| tag                   | text of tag, often cryptic
| label                 | a short human readable label for the tag
| description           | a couple of sentences describing the meaning of the tag
| show\_on\_media       | recommendation to show this tag as an option for searching Solr using the tags_id_media
| show\_on\_stories     | recommendation to show this tag as an option for searching Solr using the tags_id_stories
| is\_static            | if true, users can expect this tag and its associations not to change in major ways
| tag\_set\_name        | name field of associated tag set
| tag\_set\_label       | label field of associated tag set
| tag\_set\_description | description field of associated tag set

The show\_on\_media and show\_on\_stories fields are useful for picking out which tags are likely to be useful for
external researchers.  A tag should be considered useful for searching via tags\_id\_media or tags\_id\_stories
if show\_on\_media or show\_on\_stories, respectively, is set to true for _either_ the specific tag or its parent
tag set.

### Example

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
    }
]
```

## api/v2/tags/list/

| URL                 | Function
| ------------------- | -----------------------------
| `api/v2/tags/list`  | Return multiple tags

### Query Parameters

| Parameter       | Default    | Notes
| --------------- | ---------- | -----------------------------------------------------------------
| `last_tags_id`  | 0          | Return tags with a `tags_id` is greater than this value
| `tag_sets_id`   | none       | Return tags belonging to the given tag sets.  The most useful tag set is tag set 5.  Can be passed multiple times to return any tag belonging to any of the tag sets.
| `rows`          | 20         | Number of tags to return. Cannot be larger than 100
| `public`        | none       | If public=1, return only public tags (see below)
| `search`        | none       | Search for tags by text (see below)
| `similar_tags_id` |  none |  return list of tags with a similar

If set to 1, the public parameter will return only tags that are generally useful for public consumption.  Those tags are defined as tags for which show_on_media or show_on_stories is set to true for either the tag
or the tag's parent tag_set.  As described below in tags/single, a public tag can be usefully searched
using the Solr tags_id_media field if show_on_media is true and by the tags_id_stories field if
show_on_stories is true.

If the search parameter is set, the call will return only tags that match a case insensitive search for
the given text.  The search includes the tag and label fields of the tags plus the names and label
fields of the associated tag sets.  So a search for 'politics' will match tags whose tag or
label field includes 'politics' and also tags belonging to a tag set whose name or label field includes
'politics'.  If the search parameter has less than three characters, an empty result set will be
returned.

### Example

URL: https://api.mediacloud.org/api/v2/tags/list?rows=2&tag_sets_id=5&last_tags_id=8875026

## api/v2/tag_sets/single/

| URL                                    | Function
| -------------------------------------- | -------------------------------------------------------------
| `api/v2/tag_sets/single/<tag_sets_id>` | Return the tag set in which `tag_sets_id` equals `<tag_sets_id>`

### Query Parameters

None.

### Output description

| Field                 | Description
|-----------------------|-----------------------------------
| tags\_sets\_id        | Media Cloud internal ID of the tag set
| name                  | text of tag set, often cryptic
| label                 | a short human readable label for the tag
| description           | a couple of sentences describing the meaning of the tag
| show\_on\_media       | recommendation to show this tag as an option for searching Solr using the tags_id_media
| show\_on\_stories     | recommendation to show this tag as an option for searching Solr using the tags_id_stories

The show\_on\_media and show\_on\_stories fields are useful for picking out which tags are likely to be useful for
external researchers.  A tag should be considered useful for searching via tags\_id\_media or tags\_id\_stories
if show\_on\_media or show\_on\_stories, respectively, is set to true for _either_ the specific tag or its parent
tag set.

### Example

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

## api/v2/tag_sets/list/

| URL                     | Function
| ----------------------- | -----------------------------
| `api/v2/tag_sets/list`  | Return all `tag_sets`

### Query Parameters

| Parameter          | Default | Notes
| ------------------ | ------- | -----------------------------------------------------------------
| `last_tag_sets_id` | 0       | Return tag sets with a `tag_sets_id` greater than this value
| `rows`             | 20      | Number of tag sets to return. Cannot be larger than 100

None.

### Example

URL: https://api.mediacloud.org/api/v2/tag_sets/list

# Registration and Authentication

## Register

### `api/v2/auth/register` (POST)

| URL                    | Function             |
| ---------------------- | -------------------- |
| `api/v2/auth/register` | Register a new user. |

#### Required role

`admin`.

#### Input Description

| Field                     | Description                                                             |
| ------------------------- | ----------------------------------------------------------------------- |
| `email`                   | *(string)* Email of new user.                                           |
| `password`                | *(string)* Password of new user.                                        |
| `full_name`               | *(string)* Full name of new user.                                       |
| `notes`                   | *(string)* User's explanation on how user intends to use Media Cloud.   |
| `has_consented`           | *(integer)* Whether or not user has consented to our privacy policy.    |
| `activation_url`          | *(string)* Client's URL used for user account activation.               |

Asking user to re-enter password and comparing the two values is left to the client.

Client should prevent automated registrations with a CAPTCHA.

After successful registration, user can not immediately log in as the user needs to activate their account via email first. User will be send an email with a link to `activation_url` and the following GET parameters:

* `email` -- user's email to be used as a parameter to `auth/activate`;
* `activation_token` -- user's activation token to be used as a parameter to `auth/activate`.

#### Output Description

##### Registration was successful

```json
{
    "success": 1
}
```

After successful registraction, user is sent an email inviting him to open a link `activation_url?email=...&activation_token=...`.

##### Registration has failed

```json
{
    "error": "Reason why the user can not be registered (e.g. duplicate email)."
}
```

#### Example

URL: <https://api.mediacloud.org/api/v2/auth/register>

Input:

```json
{
    "email": "foo@bar.baz",
    "password": "qwerty1",
    "full_name": "Foo Bar",
    "notes": "Just feeling like it.",
    "has_consented": 1,
    "activation_url": "https://dashboard.mediacloud.org/activate"
}
```

Output:

```json
{
    "success": 1
}
```


### `api/v2/auth/activate` (POST)

| URL                    | Function                                                                |
| ---------------------- | ----------------------------------------------------------------------- |
| `api/v2/auth/activate` | Activate user using email and activation token from registration email. |

#### Required role

`admin`.

#### Input Description

| Field              | Description                                |
| ------------------ | ------------------------------------------ |
| `email`            | *(string)* Email of user to be activated.  |
| `activation_token` | *(string)* Activation token sent by email. |

#### Output Description

##### Activating the user was successful

```json
{
    "success": 1,
    "profile": {
        "Full profile information as in auth/profile."
    }
}
```

##### Activating the user has failed

```json
{
    "error": "Reason why user activation has failed."
}
```

#### Example

URL: <https://api.mediacloud.org/api/v2/auth/activate>

Input:

```json
{
    "email": "foo@bar.baz",
    "activation_token": "3a0e7de3ba8e19227847b59e43f2ce54c98ec897"
}
```

Output:

```json
{
    "success": 1,
    "profile": {
        "Full profile information as in auth/profile."
    }
}
```


### `api/v2/auth/resend_activation_link` (POST)

| URL                                  | Function                                           |
| ------------------------------------ | -------------------------------------------------- |
| `api/v2/auth/resend_activation_link` | Resend activation email for newly registered user. |

#### Required role

`admin`.

#### Input Description

| Field            | Description                                                                |
| ---------------- | -------------------------------------------------------------------------- |
| `email`          | *(string)* Email of newly created user to resend the activation email to.  |
| `activation_url` | *(string)* Client's URL used for user account activation.                  |

For the description of `activation_url`, see `auth/register`.

#### Output Description

##### Resending the activation email was successful

```json
{
    "success": 1
}
```

##### Resending the activation email has failed

```json
{
    "error": "Reason why the activation email can not be resent."
}
```

#### Example

URL: <https://api.mediacloud.org/api/v2/auth/resend_activation_link>

Input:

```json
{
    "email": "foo@bar.baz",
    "activation_url": "https://dashboard.mediacloud.org/activate"
}
```

Output:

```json
{
    "success": 1
}
```


## Reset password

### `api/v2/auth/send_password_reset_link` (POST)

| URL                                    | Function                                                 |
| -------------------------------------- | -------------------------------------------------------- |
| `api/v2/auth/send_password_reset_link` | Email a link to user to be used to reset their password. |

#### Required role

`admin`.

#### Input Description

| Field                | Description                                                  |
| -------------------- | ------------------------------------------------------------ |
| `email`              | *(string)* Email of user to send the password reset link to. |
| `password_reset_url` | *(string)* Client's URL used for setting new password.       |

User will be send an email with a link to `password_reset_url` and the following GET parameters:

* `email` -- user's email to be used as a parameter to `auth/reset_password`;
* `password_reset_token` -- user's password reset token to be used as a parameter to `auth/reset_password`.

#### Output Description

##### Sending the password reset link was successful

```json
{
    "success": 1
}
```

After successful send password reset API call, user is sent an email inviting him to open a link `password_reset_url?email=...&password_reset_token=...`.


##### Sending the password reset link has failed

```json
{
    "error": "Reason why the password reset link can not be sent."
}
```

#### Example

URL: <https://api.mediacloud.org/api/v2/auth/send_password_reset_link>

Input:

```json
{
    "email": "foo@bar.baz",
    "password_reset_url": "https://dashboard.mediacloud.org/reset_password"
}
```

Output:

```json
{
    "success": 1
}
```


### `api/v2/auth/reset_password` (POST)

| URL                          | Function                                                                                        |
| ---------------------------- | ----------------------------------------------------------------------------------------------- |
| `api/v2/auth/reset_password` | Reset user's password using their password reset token send by `auth/send_password_reset_link`. |

#### Required role

`admin`.

#### Input Description

| Field                  | Description                                        |
| ---------------------- | -------------------------------------------------- |
| `email`                | *(string)* Email of user to reset the password to. |
| `password_reset_token` | *(string)* Password reset token sent by email.     |
| `new_password`         | *(string)* User's new password.                    |

#### Output Description

##### Resetting the user's password was successful

```json
{
    "success": 1
}
```

##### Resetting the user's password has failed

```json
{
    "error": "Reason why the password can not be reset."
}
```

#### Example

URL: <https://api.mediacloud.org/api/v2/auth/reset_password>

Input:

```json
{
    "email": "foo@bar.baz",
    "password_reset_token": "3a0e7de3ba8e19227847b59e43f2ce54c98ec897",
    "new_password": "qwerty1"
}
```

Output:

```json
{
    "success": 1
}
```


## Log in

### `api/v2/auth/login` (POST)

| URL                 | Function                                                                       |
| ------------------- | ------------------------------------------------------------------------------ |
| `api/v2/auth/login` | Authenticate user with email + password and return user's API key and profile. |

API call is rate-limited.

#### Required role

`admin-read`.

#### Input Description

| Parameter  | Notes                                 |
| ---------- | ------------------------------------- |
| `email`    | *(string)* Email address of the user. |
| `password` | *(string)* Password of the user.      |

#### Output Description

##### User was found

```json
{
    "success": 1,
    "profile": {
        "Full profile information as in auth/profile."
    }
}
```

##### User was not found

```json
{
    "error": "User was not found, password is incorrect, user is inactive or some other reason."
}
```

#### Example

URL: <https://api.mediacloud.org/api/v2/auth/login>

Input:

```json
{
    "email": "user@email.com",
    "password": "qwerty1"
}
```

Output:

```json
{
    "success": 1,
    "profile": {
        "Full profile information as in auth/profile."
    }
}
```


## User Profile

### `api/v2/auth/profile` (GET)

| URL                     | Function                                              |
| ----------------------- | ----------------------------------------------------- |
| `api/v2/auth/profile`   | Return profile information about the requesting user. |

#### Required role

None.

#### Output Description

```json
{
    "auth_users_id": "(integer) User's unique ID (for uniquely identifying the user, try to rely on email though)",
    "email": "(string) users@email.address",
    "full_name": "(string) User's full name",
    "api_key": "(string) User's API key.",
    "notes": "(string) User's 'notes' field.",
    "created_date": "(ISO 8601 date) of when the user was created.",
    "active": "(integer) 1 if user is active (has activated account via email), 0 otherwise.",
    "has_consented": "(integer) 1 if user has consented to our privacy policy, 0 otherwise.",
    "auth_roles": [
        "(string) user-role-1",
        "(string) user-role-2"
    ],
    "limits": {
        "weekly": {
            "requests": {
                "used": "(integer) Weekly request count",
                "limit": "(integer) Weekly request limit; 0 if no limit"
            },
            "requested_items": {
                "used": "(integer) Weekly requested items count",
                "limit": "(integer) Weekly requested items limit; 0 if no limit"
            }
        },
        "max_topic_stories": "(integer) Max. topic stories"
    }
}
```

Includes a list of authentication roles for the user that give the user permission to access various parts of the backend web interface and some of the private API functionality (that for example allow editing and administration of Media Cloud's sources).

Media Cloud currently includes the following authentication roles:

| Role             | Permission Granted                                               |
| ---------------- | ---------------------------------------------------------------- |
| `admin`          | Read and write every resource                                    |
| `admin-readonly` | Read every resource                                              |
| `media-edit`     | Edit media sources                                               |
| `stories-edit`   | Edit stories                                                     |
| `tm`             | Access legacy topic mapper web interface                         |
| `tm-readonly`    | Access legacy topic mapper web interface with editing privileges |

#### Example

URL: <https://api.mediacloud.org/api/v2/auth/profile>

```json
{
    "auth_users_id": 1,
    "email": "hroberts@cyber.law.harvard.edu",
    "full_name": "Hal Roberts",
    "api_key": "bae132d8de0e0565cc9b84ec022e367f71f6dabf",
    "notes": "Media Cloud Geek",
    "created_date": "2017-03-24T03:23:47+00:00",
    "active": 1,
    "has_consented": 1,
    "auth_roles": [
        "media-edit",
        "stories-edit"
    ],
    "limits": {
        "weekly": {
            "requests": {
                "used": 200,
                "limit": 0
            },
            "requested_items": {
                "used": 2000,
                "limit": 0
            }
        },
        "max_topic_stories": 10000
    }
}
```


### `api/v2/auth/change_password` (POST)

| URL                           | Function                |
| ----------------------------- | ----------------------- |
| `api/v2/auth/change_password` | Change user's password. |

#### Required role

None.

#### Input Description

| Field          | Description                     |
| -------------- | ------------------------------- |
| `old_password` | *(string)* User's old password. |
| `new_password` | *(string)* User's new password. |

Asking user to re-enter password and comparing the two values is left to the client.

#### Output Description

##### Changing the user's password was successful

```json
{
    "success": 1
}
```

##### Changing the user's password has failed

```json
{
    "error": "Reason why the password can not be changed."
}
```

#### Example

URL: <https://api.mediacloud.org/api/v2/auth/change_password>

Input:

```json
{
    "old_password": "qwerty1",
    "new_password": "qwerty1",
}
```

Output:

```json
{
    "success": 1
}
```


### `api/v2/auth/reset_api_key` (POST)

| URL                         | Function              |
| --------------------------- | --------------------- |
| `api/v2/auth/reset_api_key` | Reset user's API key. |

#### Required role

None.

#### Output Description

##### Resetting user's API key was successful

```json
{
    "success": 1,
    "profile": {
        "Full profile information as in auth/profile, including the new API key."
    }
}
```

##### Resetting user's API key has failed

```json
{
    "error": "Reason why resetting user's API key has failed."
}
```

#### Example

URL: <https://api.mediacloud.org/api/v2/auth/reset_api_key>

Output:

```json
{
    "success": 1,
    "profile": {
        "Full profile information as in auth/profile, including the new API key."
    }
}
```


# Stats

## api/v2/stats/list

| URL                     | Function
| ----------------------- | -----------------
| `api/v2/stats/list` | Return basic summary stats about total sources, stories, feeds, etc processed by Media Cloud

### Query Parameters

( none )

### Output Description

| Field | Description |
|-|-|
| total_stories | total number of stories in the Media Cloud database |
| total_downloads | total number of downloads (including stories and feeds) in the Media Cloud database |
| total_sentences | total number of sentences in the Media Cloud database |
| active_crawled_feeds | number of syndicated feeds with a story in the last 180 days |
| active_crawled_media | number of media source with an active crawled feed |
| daily_stories | number of stories added yesterday |
| daily_downloads | number of downloads added yesterday |

### Example

URL: https://api.mediacloud.org/api/v2/stats/list

```json
{
    "total_stories": 516145344,
    "total_downloads": 941078656,
    "total_sentences": 6899028480,
    "active_crawled_media": 123,
    "active_crawled_feeds": 123,
    "daily_stories": 123,
    "daily_downloads": 123,
}
```

# Util

## api/v2/util/is_syndicated_ap (POST)

Detect whether a given block of content is likely to be ap syndicated content by looking for certain signals in the text
(for example 'boston (ap)') and by comparing the text to the text of ap content in the Media Cloud database.

### Input Description

| Field         | Description
| ------------------ | ----------------------------------------------------------------
| `content`          | text or html content

### Output Description

| Field                        | Description
| ---------------------------- | -----------------------------------------------------------------------------
| is_syndicated                | 1 if the story is syndicated, 0 otherwise

### Example

URL: https://api.mediacloud.org/api/v2/util/is_syndicated_ap

Input:

```json
{
    "content": "WASHINGTON (AP) -- Republican Sen. Marco Rubio declared Thursday he will vote against the GOP'S sweeping tax package unless negotiators expand its child tax credit, jeopardizing the Republicans' razor-thin margin as they try to muscle the $1.5 trillion bill through Congress next week."
}
```

```json
{
    "is_syndicated": 1
}
```

# Extended Examples

Note: The Python examples below are included for reference purposes. However, a [Python client]( https://github.com/c4fcm/MediaCloud-API-Client ) for our API is now available and most Python users will find it much easier to use the API client instead of making web requests directly.

## Output Format / JSON

The format of the API responses is determined by the `Accept` header on the request. The default is `application/json`. Other supported formats include `text/html`, `text/x-json`, and `text/x-php-serialization`. It's recommended that you explicitly set the `Accept` header rather than relying on the default.

Here's an example of setting the `Accept` header in Python:

```python
import pkg_resources

import requests
assert pkg_resources.get_distribution("requests").version >= '1.2.3'

r = requests.get('https://api.mediacloud.org/api/v2/media/list',
    params = params,
    headers = { 'Accept': 'application/json'},
    headers = { 'Accept': 'application/json'}
)

data = r.json()
```

## Create a CSV file with all media sources.

```python
media = []
last_media_id = 0
rows  = 1000
while True:
    params = { 'last_media_id': last_media_id, 'rows': rows, 'key': MY_KEY }
    print "last_media_id:{} rows:{}".format( last_media_id, rows)
    r = requests.get( 'https://api.mediacloud.org/api/v2/media/list', params = params, headers = { 'Accept': 'application/json'} )
    data = r.json()

    if len(data) == 0:
        break

    last_media_id = data[-1]['media_id']
    media.extend( data )

fieldnames = [
    u'media_id',
    u'url',
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

The you almost always want to search by a specific media source or media collection.  The easiest way to find a relevant media
collection is to use our [Sources Tool](https://sources.mediacloud.org).  The URL for a the US Mainstream Media media collection in
the sources tool looks like this:

https://sources.mediacloud.org/#media-tag/8875027/details

The number in that URL is the tags_id of the media collection.

## Grab stories by querying stories_public/list

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
    params = {
        'last_processed_stories_id': start,
        'rows': rows,
        'q': 'media_id:1',
        'fq': 'publish_date:[2010-10-01T00:00:00Z TO 2010-11-01T00:00:00Z]',
        'key': MY_KEY
    }

    print "Fetching {} stories starting from {}".format( rows, start)
    r = requests.get( 'https://api.mediacloud.org/api/v2/stories_public/list/', params = params, headers = { 'Accept': 'application/json'} )
    stories = r.json()

    if len(stories) == 0:
        break

    start = stories[ -1 ][ 'processed_stories_id' ]

    process_stories( stories )
```

## Get word counts for top words for sentences matching 'trayvon' in US Mainstream Media during April 2012

### Find the media collection

As above, find the tags_id of the US Mainstream Media collection (8875027).

### Make a request for the word counts based on `tags_id_media`, sentence text and date range

One way to appropriately restrict the data is by setting the `q` parameter to restrict by sentence content and then the `fq` parameter twice to restrict by `tags_id_media` and `publish_date`.

Below `q` is set to `"text:trayvon"` and `fq` is set to `"tags_iud_media:8875027" and "publish_date:[2012-04-01T00:00:00.000Z TO 2013-05-01T00:00:00.000Z]"`. (Note that ":", "[", and "]" are URL encoded.)

```bash
curl 'https://api.mediacloud.org/api/v2/wc?q=text:trayvon&fq=tags_iud_media:8875027&fq=publish_date:%5B2012-04-01T00:00:00.000Z+TO+2013-05-01T00:00:00.000Z%5D'
```

Alternatively, we could use a single large query by setting `q` to `"text:trayvon AND tags_id_media:8875027 AND publish_date:[2012-04-01T00:00:00.000Z TO 2013-05-01T00:00:00.000Z]"`:

```bash
curl 'https://api.mediacloud.org/api/v2/wc?q=text:trayvon+AND+tags_id_media:8875027+AND+publish_date:%5B2012-04-01T00:00:00.000Z+TO+2013-05-01T00:00:00.000Z%5D&fq=tags_id_media:8875027&fq=publish_date:%5B2012-04-01T00:00:00.000Z+TO+2013-05-01T00:00:00.000Z%5D'
```


## Get word counts for top words for sentences with the tag `'odd'` in `tag_set = 'ts'`


### Find the `tag_sets_id` for `'ts'`

The user requests a list of all tag sets.

```bash
curl https://api.mediacloud.org/api/v2/tag_sets/list
```

```json
[
    {
        "tag_sets_id": 597,
        "name": "gv_country"
    },
    {
        "tag_sets_id": 800,
        "name": "ts"
    }
]
```

*(Additional tag sets skipped for brevity.)*

Looking through the output, the user sees that the `tag_sets_id` is 800.


## Find the `tags_id` for `'odd'` given the `tag_sets_id`

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

### Request a word count using the `tags_id`

Assume that the user determined that the `tags_id` was 12345678 using the above code.  The following will return
the word count for all sentences in stories belonging to any media source associated with tag 12345678.

```bash
curl 'https://api.mediacloud.org/api/v2/wc?q=tags_id_media:12345678'
```

## Grab stories from 10 January 2014 with the tag `'foo:bar'`

### Find the `tag_sets_id` for `'foo'`

See the "Get Word Counts for Top Words for Sentences with the Tag `'odd'` in `tag_set = 'ts'`" example above.

### Find the `tags_id` for `'bar'` given the `tag_sets_id`

See the "Get Word Counts for Top Words for Sentences with the Tag `'odd'` in `tag_set = 'ts'`" example above.

## Grab stories by querying stories_public/list

We assume the `tags_id` is 678910.

```python
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
