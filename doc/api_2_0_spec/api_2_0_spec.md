% Media Cloud API Version 2
% David Larochelle
%

#API URLs

*Note:* by default the API only returns a subset of the available fields in returned objects. The returned fields are those that we consider to be the most relevant to users of the API. If the `all_fields` parameter is provided and is non-zero, then a more complete list of fields will be returned. For space reasons, we do not list the `all_fields` parameter on individual API descriptions.

## Authentication

Every call below includes a `key` parameter which will authenticate the user to the API service.  The key parameter is excluded
from the examples in the below sections for brevity.

### Example

http://www.mediacloud.org/api/v2/media/single/1?key=KRN4T5JGJ2A

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

URL: http://www.mediacloud.org/api/v2/media/single/1

Response:

```json
[
  {
    "url": "http:\/\/nytimes.com",
    "name": "New York Times",
    "media_id": 1,
    "media_source_tags": [
      {
        "tags_id": 1,
        "tag_sets_id": 1,
        "tag_set": "media_type",
        "tag": "newspapers"
      },
      {
        "tag_sets_id": 3,
        "tag_set": "usnewspapercirculation",
        "tag": "3",
        "tags_id": 109
      },
      {
        "tags_id": 6071565,
        "tag_sets_id": 17,
        "tag_set": "word_cloud",
        "tag": "include"
      },
      {
        "tag": "default",
        "tag_set": "word_cloud",
        "tag_sets_id": 17,
        "tags_id": 6729599
      },
      {
        "tag": "adplanner_english_news_20090910",
        "tag_set": "collection",
        "tag_sets_id": 5,
        "tags_id": 8874930
      },
      {
        "tag_sets_id": 5,
        "tag_set": "collection",
        "tag": "ap_english_us_top25_20100110",
        "tags_id": 8875027
      }
    ],
    "media_sets": [
      {
        "set_type": "medium",
        "media_sets_id": 24,
        "name": "New York Times",
        "description": null
      }
    ]
  }
]
```


### api/v2/media/list/

| URL                 | Function
| ------------------- | -----------------------------
| `api/v2/media/list` | Return multiple media sources

#### Query Parameters 

| Parameter       | Default | Notes
| --------------- | ------- | -----------------------------------------------------------------
| `last_media_id` | 0       | Return media sources with a `media_id` greater than this value
| `rows`          | 20      | Number of media sources to return. Cannot be larger than 100

#### Example

URL: http://www.mediacloud.org/api/v2/media/list?last_media_id=1&rows=2

Output format is the same as for api/v2/media/single above.

## Media Sets

A media set is a collection of media sources, such as U.S. Top 25 Mainstream Media or Global Voices Cited Blogs.  Each 
media source can belong to zero or more media sets.  Each media set belongs to zero or more dashboards.

### api/v2/media_set/single

| URL                                       | Function
| ----------------------------------------- | ----------------------------------------------------------------------
| `api/v2/media_set/single/<media_sets_id>` | Return the media set in which `media_sets_id` equals `<media_sets_id>`

#### Query Parameters

None.

#### Example

http://www.mediacloud.org/api/v2/media_sets/single/1

```json
[
  {
    "media_sets_id": 1,
    "name": "Top 25 Mainstream Media",
    "description": "Top 25 mainstream media sources by monthly unique users from the U.S. according to the Google AdPlanner service.",
    "media": [
      {
        "media_id": 1,
        "url": "http:\/\/nytimes.com",
        "name": "New York Times"
      },
      {
        "media_id": 2,
        "url": "http:\/\/washingtonpost.com",
        "name": "Washington Post"
      },
      {
        "media_id": 4,
        "url": "http:\/\/www.usatoday.com",
        "name": "USA Today"
      },
      {
        "media_id": 6,
        "url": "http:\/\/www.latimes.com\/",
        "name": "Los Angeles Times"
      },
      {
        "media_id": 7,
        "url": "http:\/\/www.nypost.com\/",
        "name": "The New York Post"
      },
      {
        "media_id": 8,
        "url": "http:\/\/www.nydailynews.com\/",
        "name": "The Daily News New York"
      },
      {
        "media_id": 14,
        "url": "http:\/\/www.sfgate.com\/",
        "name": "San Francisco Chronicle"
      },
      {
        "media_id": 314,
        "url": "http:\/\/www.huffingtonpost.com\/",
        "name": "The Huffington Post"
      },
      {
        "media_id": 1089,
        "url": "http:\/\/www.reuters.com\/",
        "name": "Reuters"
      },
      {
        "media_id": 1092,
        "url": "http:\/\/www.foxnews.com\/",
        "name": "FOX News"
      },
      {
        "media_id": 1094,
        "url": "http:\/\/www.bbc.co.uk\/?ok",
        "name": "BBC"
      },
      {
        "media_id": 1095,
        "url": "http:\/\/www.cnn.com\/",
        "name": "CNN"
      },
      {
        "media_id": 1098,
        "url": "http:\/\/www.newsweek.com\/",
        "name": "Newsweek "
      },
      {
        "media_id": 1104,
        "url": "http:\/\/www.forbes.com\/",
        "name": "Forbes"
      },
      {
        "media_id": 1149,
        "url": "http:\/\/www.msnbc.msn.com\/",
        "name": "MSNBC"
      },
      {
        "media_id": 1747,
        "url": "http:\/\/www.dailymail.co.uk\/home\/index.html",
        "name": "Daily Mail"
      },
      {
        "media_id": 1750,
        "url": "http:\/\/www.telegraph.co.uk\/",
        "name": "Daily Telegraph"
      },
      {
        "media_id": 1751,
        "url": "http:\/\/www.guardian.co.uk\/",
        "name": "Guardian"
      },
      {
        "media_id": 1752,
        "url": "http:\/\/www.cbsnews.com\/",
        "name": "CBS News"
      },
      {
        "media_id": 4415,
        "url": "http:\/\/cnet.com",
        "name": "CNET"
      },
      {
        "media_id": 4418,
        "url": "http:\/\/examiner.com",
        "name": "Examiner.com"
      },
      {
        "media_id": 4419,
        "url": "http:\/\/time.com",
        "name": "TIME.com"
      }
    ],
  }
]
```

### api/v2/media_sets/list

| URL                      | Function
| ------------------------ | --------------------------
| `api/v2/media_sets/list` | Return multiple media sets

#### Query Parameters 

| Parameter            | Default | Notes
| -------------------- | ------- | -----------------------------------------------------------------
| `last_media_sets_id` | 0       | Return media sets with `media_sets_id` is greater than this value
| `rows`               | 20      | Number of media sets to return. Cannot be larger than 100

#### Example

URL: http://www.mediacloud.org/api/v2/media_sets/list?rows=1&last_media_sets_id=1

Output is the same as the api/v2/media_set/single example above.

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

URL: http://www.mediacloud.org/api/v2/feeds/single/1

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

URL: http://www.mediacloud.org/api/v2/feeds/list?media_id=1

Output format is the same as for api/v2/feeds/single above.

## Dashboards

A dashboard is a collection of media sets, for example US/English or Russian.  Dashboards are useful for finding the core
media sets related to some topic, usually a country.  Each media set can belong to zero or more dashboards.

### api/v2/dashboard/single

| URL                                       | Function
| ----------------------------------------- | ----------------------------------------------------------------------
| `api/v2/dashboard/single/<dashboards_id>` | Return the dashboard for which `dashboards_id` equals `<dashboards_id>`

#### Query Parameters 

| Parameter     | Default | Notes
| ------------- | ------- | -------------------------------------------------------------------------------------
| `nested_data` | 1       | If 0, return only the `name` and `dashboards_id`.<br />If 1, return nested information about the dashboard's `media_sets` and their `media`.

#### Example

http://www.mediacloud.org/api/v2/dashboards/single/2

```json
[
   {
      "name":"dashboard 2",
      "dashboards_id": "2",
      "media_sets":
      [
      {
         "name":"set name",
         "media_sets_id": "2",
         "media":[
            {
               "name":"source 1 name",
               "media_id":"source 1 media id",
               "url":"http://source1.com"
            },
            {
               "name":"source 2 name",
               "media_id":"source 2 media id",
               "url":"http://source2.com"
            },

         ]
      }
   ]
}
]
```

### api/v2/dashboards/list

| URL                      | Function
| ------------------------ | --------------------------
| `api/v2/dashboards/list` | Return multiple dashboards

#### Query Parameters 

| Parameter            | Default | Notes
| -------------------- | ------- | -------------------------------------------------------------------------------------
| `last_dashboards_id` | 0       | Return dashboards in which `dashboards_id` greater than this value
| `rows`               | 20      | Number of dashboards to return. Cannot be larger than 100
| `nested_data`        | 1       | If 0, return only the `name` and `dashboards_id`.<br />If 1, return nested information about the dashboard's `media_sets` and their `media`.

#### Example

URL: http://www.mediacloud.org/api/v2/dashboards/list?rows=1&last_dashboards_id=1

Output is the same as the api/v2/dashboard/single example above.

## Stories

A story represents a single published piece of content.  Each unique URL downloaded from any syndicated feed within 
a single media source is represented by a single story.  For example, a single New York Times newspaper story is a 
Media Cloud story, as is a single Instapundit blog post.  Only one story may exist for a given title for each 24 hours 
within a single media source.

The `story_text` of a story is either the content of the description field in the syndicated field or the extracted 
text of the content downloaded from the story's URL at the `collect_date`, depending on whether our full text RSS 
detection system has determined that the full text of each story can be found in the RSS of a given media source.

### Output description

The following table describes the meaning and origin of fields returned by both api/v2/stories/single and api/v2/stories/list in which we felt clarification was necessary.

| Field               | Description
| ------------------- | ----------------------------------------------------------------------
| `title`             | The story title as defined in the RSS feed. May contain HTML (depending on the source).
| `description`       | The story description as defined in the RSS feed. May contain HTML (depending on the source).
| `full_text_rss`     | If 1, the text of the story was obtained through the RSS feed.<br />If 0, the text of the story was obtained by extracting the article text from the HTML.
| `story_text`        | The text of the story.<br />If `full_text_rss` is non-zero, this is formed by stripping HTML from the title and description and concatenating them.<br />If `full_text_rss` is zero, this is formed by extracting the article text from the HTML.
| `story_sentences`   | A list of sentences in the story.<br />Generated from `story_text` by splitting it into sentences and removing any duplicate sentences occurring within the same source for the same week.
| `raw_1st_download`  | The contents of the first HTML page of the story.<br />Available regardless of the value of `full_text_rss`.<br />*Note:* only provided if the `raw_1st_download` parameter is non-zero.
| `publish_date`      | The publish date of the story as specified in the RSS feed.
| `tags` | A list of any tags associated with this story, including those written through the write-back api.
| `collect_date`      | The date the RSS feed was actually downloaded.
| `guid`              | The GUID field in the RSS feed. Defaults to the URL if no GUID is specified in the RSS feed.
| `corenlp`           | The raw json result from running the story text through the CoreNLP pipeline.


### api/v2/stories/single

| URL                                  | Function
| ------------------------------------ | ------------------------------------------------------
| `api/v2/stories/single/<stories_id>` | Return the story for which `stories_id` equals `<stories_id>`

#### Query Parameters 

| Parameter          | Default | Notes
| ------------------ | ------- | -----------------------------------------------------------------
| `raw_1st_download` | 0       | If non-zero, include the full HTML of the first page of the story
| `corenlp`          | 0       | If non-zero, include the corenlp json document with each story and each sentence

#### Example

Note: This fetches data on the CC licensed Global Voices story ["Myanmar's new flag and new name"](http://globalvoicesonline.org/2010/10/26/myanmars-new-flag-and-new-name/#comment-1733161) from November 2010.

URL: http://www.mediacloud.org/api/v2/stories/single/27456565


```json
[
  {
    "db_row_last_updated": null,
    "full_text_rss": 0,
    "description": "<p>Both the previously current and now current Burmese flags look ugly and ridiculous!  Burma once had a flag that was actually better looking.  Also Taiwan&#8217;s flag needs to change!  it is a party state flag representing the republic of china since 1911 and Taiwan\/Formosa was Japanese colony since 1895.  A new flag representing the land, people and history of Taiwan needs to be given birth to and flown!<\/p>\n",
    "language": "en",
    "title": "Comment on Myanmar's new flag and new name by kc",
    "fully_extracted": 1,
    "collect_date": "2010-11-24 15:33:39",
    "url": "http:\/\/globalvoicesonline.org\/2010\/10\/26\/myanmars-new-flag-and-new-name\/comment-page-1\/#comment-1733161",
    "guid": "http:\/\/globalvoicesonline.org\/?p=169660#comment-1733161",
    "publish_date": "2010-11-24 04:05:00",
    "media_id": 1144,
    "stories_id": 27456565,
    "story_texts_id": null,
    "story_text": " \t\t\t\t\t\tMyanmar's new flag and new name\t\t    The new flag, designated in the 2008 Constitution, has a central star set against a yellow, green and red background.   The old flags will be lowered by government department officials who were born on a Tuesday, while the new flags will be raised by officials born on a Wednesday.   <SENTENCES SKIPPED BECAUSE OF SPACE REASONS> You know That big white star is also the only star on the colors of Myanmar's tatmadaw, navy, air force and police force. This flag represent only the armed forces.  ",
    "story_tags": [ 1234235 ],
    "story_sentences": [
      {
        "language": "en",
        "db_row_last_updated": null,
        "sentence": "Myanmar's new flag and new name The new flag, designated in the 2008 Constitution, has a central star set against a yellow, green and red background.",
        "sentence_number": 0,
        "story_sentences_id": "525687757",
        "media_id": 1144,
        "stories_id": 27456565,
        "tags": [ 123 ],
        "publish_date": "2010-11-24 04:05:00"
      },
      {
        "sentence_number": 1,
        "story_sentences_id": "525687758",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "language": "en",
        "db_row_last_updated": null,
        "tags": [ 123 ],
        "sentence": "The old flags will be lowered by government department officials who were born on a Tuesday, while the new flags will be raised by officials born on a Wednesday."
      },
      // SENTENCES SKIPPED BECAUSE OF SPACE REASONS
      {
        "language": "en",
        "db_row_last_updated": null,
        "tags": [ 123 ],
        "sentence": "You know That big white star is also the only star on the colors of Myanmar's tatmadaw, navy, air force and police force.",
        "story_sentences_id": "525687808",
        "sentence_number": 51,
        "publish_date": "2010-11-24 04:05:00",
        "stories_id": 27456565,
        "media_id": 1144
      },
      {
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "sentence_number": 52,
        "story_sentences_id": "525687809",
        "db_row_last_updated": null,
        "sentence": "This flag represent only the armed forces.",
        "tags": [ 123 ],
        "language": "en"
      }
    ],
  }
]
```

### api/v2/stories/list
  
| URL                             | Function
| ------------------------------- | ---------------------------------
| `api/v2/stories/list` | Return multiple processed stories

#### Query Parameters 

| Parameter                    | Default | Notes
| ---------------------------- | ------- | ------------------------------------------------------------------------------
| `last_processed_stories_id`  | 0       | Return stories in which the `processed_stories_id` is greater than this value.
| `rows`                       | 20      | Number of stories to return.
| `raw_1st_download`           | 0       | If non-zero, include the full HTML of the first page of the story.
| `corenlp`                    | 0       | If non-zero, include the corenlp json document with each story and each sentence
| `q`                          | null    | If specified, return only results that match the given Solr query.  Only one `q` parameter may be included.
| `fq`                         | null    | If specified, file results by the given Solr query.  More than one `fq` parameter may be included.


The `last_processed_stories_id` parameter can be used to page through these results. The API will return stories with a 
`processed_stories_id` greater than this value.  To get a continuous stream of stories as they are processed by Media Cloud, 
the user must make a series of calls to api/v2/stories/list in which `last_processed_stories_id` for each 
call is set to the `processed_stories_id` of the last story in the previous call to the API.

*Note:* `stories_id` and `processed_stories_id` are separate values. The order in which stories are processed is different than the `stories_id` order. The processing pipeline involves downloading, extracting, and vectoring stories. Requesting by the `processed_stories_id` field guarantees that the user will receive every story (matching the query criteria if present) in
the order it is processed by the system.

The `q` and `fq` parameters specify queries to be sent to a Solr server that indexes all Media Cloud stories.  The Solr
server provides full text search indexing of each sentence collected by Media Cloud.  All content is stored as individual 
sentences.  The api/v2/stories/list call searches for sentences matching the `q` and / or `fq` parameters if specified and
the stories that include at least one sentence returned by the specified query.

The `q` and `fq` parameters are passed directly through to Solr.  Documentation of the format of the `q` and `fq` parameters is [here](http://lucene.apache.org/core/4_6_1/queryparser/org/apache/lucene/queryparser/classic/package-summary.html#package_description).  All the return fields (in the example return value in the api/v2/sentences/list call below) may be used 
as solr query parameters, for example 'sentence:obama AND media_id:1'. Be aware that ':' is usually replaced with '%3A' in programmatically generated URLs.

#### Example

The output of these calls is in exactly the same format as for the api/v2/stories/single call.

URL: http://www.mediacloud.org/api/v2/stories/list?last_processed_stories_id=8625915

Return a stream of all stories processed by Media Cloud, greater than the `last_processed_stories_id`.

URL: http://www.mediacloud.org/api/v2/stories/list?last_processed_stories_id=2523432&q=sentence:obama+AND+media_id:1

Return a stream of all stories from The New York Times mentioning `'obama'` greater than the given `last_processed_stories_id`.

## Sentences

The `story_text` of every story processed by Media Cloud is parsed into individual sentences.  Duplicate sentences within
the same media source in the same week are dropped (the large majority of those duplicate sentences are 
navigational snippets wrongly included in the extracted text by the extractor algorithm).

### api/v2/sentences/list

#### Query Parameters

| Parameter | Default | Notes
| --------- | ---------------- | ----------------------------------------------------------------
| `q`       | n/a              | `q` ("query") parameter which is passed directly to Solr
| `fq`      | `null`           | `fq` ("filter query") parameter which is passed directly to Solr
| `start`   | 0                | Passed directly to Solr
| `rows`    | 1000             | Passed directly to Solr
| `sort`    | publish_date_asc | publish_date_asc, publish_date_desc, or random

--------------------------------------------------------------------------------------------------------

Other than 'sort', these parameters are passed directly through to Solr (see above).  The sort parameter must be
one of the listed above and determines the order of the sentences returned.

#### Example

Fetch 10 sentences containing the word 'obama' from The New York Times

URL:  http://www.mediacloud.org/api/v2/sentences/list?q=sentence:obama&rows=10&fq=media_id:1

```json
{
  "responseHeader":{
    "params":{
      "sort":"random_1 asc",
      "df":"sentence",
      "wt":"json",
      "q":"sentence:obama",
      "fq":"media_id:1",
      "rows":"10",
      "start":"0"
    },
    "status":0,
    "QTime":20
  },
  "response":{
    "numFound":94171,
    "docs":[
      {
        "sentence":"Mr. Obama played golf on Sunday and again on Monday.",
        "media_id":1,
        "publish_date":"2013-08-13 00:55:48",
        "sentence_number":3,
        "stories_id":146975599,
        "_version_":1465531175907885056,
        "story_sentences_id":"1693567329"
      },
      {
        "sentence":"Without mentioning them by name, it takes on Charles and David Koch, the wealthy conservative businessmen who have opposed Mr. Obama through the political advocacy group Americans for Prosperity.",
        "media_id":1,
        "publish_date":"2012-01-19 01:12:10",
        "sentence_number":5,
        "stories_id":51549022,
        "_version_":1465513962638409730,
        "story_sentences_id":"902231969"
      },
      {
        "sentence":"Former presidential speechwriters said Lincoln’s few words would make it even more difficult for Mr. Obama to find ones that feel fresh.",
        "media_id":1,
        "publish_date":"2013-08-22 00:51:42",
        "sentence_number":36,
        "stories_id":149735751,
        "_version_":1465531727373926400,
        "story_sentences_id":"1723403496"
      },
      {
        "sentence":"Though Mr. Obama is expected to address how the peace process fits into the broader changes in the Middle East, officials said they did not expect him to lay out a detailed American blueprint to revive the negotiations, which have been paralyzed since September.",
        "media_id":1,
        "publish_date":"2011-05-17 17:10:14",
        "sentence_number":9,
        "stories_id":36107537,
        "_version_":1465517874643730432,
        "story_sentences_id":"684054351"
      },
      {
        "sentence":"“The reason I’m so animated about defeating Barack Obama is because he’s failed the American people,” Mr. Romney said, speaking outside at an energy company.",
        "media_id":1,
        "publish_date":"2012-06-14 13:17:37",
        "sentence_number":68,
        "stories_id":169631466,
        "_version_":1465545382125633537,
        "story_sentences_id":"2085799723"
      },
      {
        "sentence":"Sarah Palin said Obama was guilty of “shuck and jive” on Benghazi.",
        "media_id":1,
        "publish_date":"2012-10-27 23:02:01",
        "sentence_number":27,
        "stories_id":92275227,
        "_version_":1465520856365006849,
        "story_sentences_id":"1060529064"
      },
      {
        "sentence":"Still, Democrats openly worried that if Mr. Obama could not drive a harder bargain when he holds most of the cards, he will give up still more Democratic priorities in the coming weeks, when hard deadlines will raise the prospects of a government default first, then a government shutdown.",
        "media_id":1,
        "publish_date":"2013-01-01 02:10:42",
        "sentence_number":24,
        "stories_id":96795610,
        "_version_":1465523519766921216,
        "story_sentences_id":"1112283342"
      },
      {
        "sentence":"Mr. Obama agreed to the far-reaching penalties after the White House negotiated language that would allow him to waive them against foreign financial institutions.",
        "media_id":1,
        "publish_date":"2012-02-06 17:07:35",
        "sentence_number":12,
        "stories_id":72982936,
        "_version_":1465514836620214273,
        "story_sentences_id":"908488464"
      },
      {
        "sentence":"“We believe the Syrian government to be systematically persecuting its own people on a vast scale.” On Tuesday, the Obama administration added to the economic pressure on Mr. Assad’s government, freezing the United States assets of Foreign Minister Walid al-Moualem and two other officials.",
        "media_id":1,
        "publish_date":"2011-08-31 19:30:38",
        "sentence_number":18,
        "stories_id":40984774,
        "_version_":1465516934096224256,
        "story_sentences_id":"762139692"
      },
      {
        "sentence":"Mr. Obama set the standard with the $745 million he raised in 2008 after opting not to participate in the post-Watergate public financing system, under which candidates received taxpayer funds in return for accepting limits on their spending.",
        "media_id":1,
        "publish_date":"2012-06-22 19:30:32",
        "sentence_number":23,
        "stories_id":83442616,
        "_version_":1465520768804716544,
        "story_sentences_id":"983218944"
      }
    ],
    "start":0
  }
}
```

## Word Counting

### api/v2/wc/list

Returns word frequency counts of the 5000 most commwords in all sentences returned by 
querying Solr using the `q` and `fq` parameters, with stopwords removed.  Words are stemmed
before being counted.  For each word, the call returns the stem and the full term most used 
with the given stem (for example, in the below example, 'romnei' is the stem that appeared 
7969 times and 'romney' is the word that was most commonly stemmed into 'romnei').

#### Query Parameters

| Parameter | Default | Notes
| --------- | ------- | ----------------------------------------------------------------
| `q`       | n/a     | `q` ("query") parameter which is passed directly to Solr
| `fq`      | `null`  | `fq` ("filter query") parameter which is passed directly to Solr
| `l`       | `en`    | space separated list of languages to use for stopwording and stemming

See above /api/v2/stories/list for Solr query syntax.

By default, the system stems and stopwords the list in English.  If you specify the 'l' parameter, 
the system will stem and stopword the words by each of the listed langauges serially.  To do no stemming 
or stopwording, specify 'none'.  The following language are supported (by 2 letter language code): 
'da' (Danish), 'de' (German), 'en' (English), 'es' (Spanish), 'fi' (Finnish), 'fr' (French),
'hu' (Hungarian), 'it' (Italian), 'lt' (Lithuanian), 'nl' (Dutch), 'no' (Norwegian), 'pt' (Portuguese),
'ro' (Romanian), 'ru' (Russian), 'sv' (Swedish), 'tr' (Turkish).


### Example

Obtain word frequency counts for all sentences containing the word `'obama'` in The New York Times

URL:  http://www.mediacloud.org/api/v2/wc/list?q=sentence:obama&fq=media_id:1

```json
[
  {
    "count": 91778,
    "stem": "obama",
    "term": "obama"
  },
  {
    "count": 10455,
    "stem": "republican",
    "term": "republicans"
  },
  {
    "count": 7969,
    "stem": "romnei",
    "term": "romney"
  },
  // WORDS SKIPPED FOR SPACE REASONS
  {
    "count": 22,
    "stem": "swell",
    "term": "swelling"
  },
  {
    "count": 22,
    "stem": "savvi",
    "term": "savvy"
  },
  {
    "count": 22,
    "stem": "unspecifi",
    "term": "unspecified"
  }
]
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

#### Example

Fetching information on the tag 8876989.

URL: http://www.mediacloud.org/api/v2/tags/single/8876989

Response:

```json
[
  {
    "tags_id": 8876989,
    "tag": "japan",
    "tag_sets_id": 597
   }
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
| `tag_sets_id`   | (required) | Return tags belonging to the given tag set.
| `rows`          | 20         | Number of tags to return. Cannot be larger than 100

#### Example

URL: http://www.mediacloud.org/api/v2/tags/list?last_tags_id=1&rows=2&tag_sets_id=597

```json
[
  {
    "tags_id": 8876989,
    "tag": "japan",
    "tag_sets_id": 597,
   }
  {
    "tags_id": 8876990,
    "tag": "brazil",
    "tag_sets_id": 597
   }
]
```

### api/v2/tag_sets/single/

| URL                                    | Function
| -------------------------------------- | -------------------------------------------------------------
| `api/v2/tag_sets/single/<tag_sets_id>` | Return the tag set in which `tag_sets_id` equals `<tag_sets_id>`

#### Query Parameters 

None.

#### Example

Fetching information on the tag set 597.

URL: http://www.mediacloud.org/api/v2/tag_sets/single/597

Response:

```json
[
  {
    "tag_sets_id": 597,
    "name": "gv_country"
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

URL: http://www.mediacloud.org/api/v2/tag_sets/list

```json
[
  {
    "tag_sets_id": 597,
    "name": "gv_country"
   },
   // additional tag sets skipped for space
]
```

## Write Back API

These calls allow users to push data into the PostgreSQL database. This data will then be imported from Postgresql into Solr.

### api/v2/stories/put_tags (PUT)

| URL                          | Function
| ---------------------------- | --------------------------------------------------
| `api/v2/stories/put_tags`    | Add tags to a story. Must be a PUT request.

#### Query Parameters

| Parameter    | Notes
| ------------ | -----------------------------------------------------------------
| `story_tag`  | The `stories_id` and associated tag in `stories_id,tag` format.  Can be specified more than once.

Each `story_tag` parameter associates a single story with a single tag.  To associate a story with more than one tag,
include this parameter multiple times.  A single call can include multiple stories as well as multiple tags.  Users
are encouraged to batch writes for multiple stories into a single call to avoid the web server overhead of many small
web service calls.

The `story_tag` parameter consists of the `stories_id` and the tag information, separated by a comma.  The tag part of 
the parameter value can be in one of two formats -- either the `tags_id` of the tag or the tag set name and tag
in `<tag set>:<tag>` format, for example `gv_country:japan`.
    
If the tag is specified in the latter format and the given tag set does not exist, a new tag set with that 
name will be created owned by the current user.  If the tag does not exist, a new tag will be created 
within the given tag set.

A user may only write put tags (or create new tags) within a tag set owned by that user.

#### Example

Add tag ID 5678 to story ID 1234.

```
curl -X PUT -d story_tag=1234,5678 http://www.mediacloud.org/api/v2/stories/put_tags
```

Add the `gv_country:japan` and the `gv_country:brazil` tags to story 1234 and the `gv_country:japan` tag to 
story 5678.

```
curl -X PUT -d story_tag=1234,gv_country:japan -d story_tag=1234,gv_country:brazil -d story_tag=5678,gv_country:japan http://www.mediacloud.org/api/v2/stories/put_tags
```

### api/v2/sentences/put_tags (PUT)

| URL                                  | Function
| ------------------------------------ | -----------------------------------------------------------
| `api/v2/sentences/put_tags`          | Add tags to a story sentence. Must be a PUT request.

#### Query Parameters 

| Parameter            | Notes
| -------------------- | --------------------------------------------------------------------------
| `sentence_tag`       | The `story_sentences_id` and associated tag in `story_sentences_id,tag` format.  Can be specified more than once.

The format of the sentences write back call is the same as for the stories write back call above, but with the `story_sentences_id`
substituted for the `stories_id`.  As with the stories write back call, users are strongly encouraged to 
included multiple sentences (including sentences for multiple stories) in a single call to avoid
web service overhead.

#### Example

Add the `gv_country:japan` and the `gv_country:brazil` tags to story sentence 12345678 and the `gv_country:japan` tag to 
story sentence 56781234.

```
curl -X PUT -d sentence_tag=12345678,gv_country:japan -d sentence_tag=12345678,gv_country:brazil -d sentence_tag=56781234,gv_country:japan http://www.mediacloud.org/api/v2/sentences/put_tags
```

## Authentication API

The Authentication API allows a client to fetch an IP-address-limited authentication token for a user.

### api/v2/auth/single (GET)

| URL                          | Function
| ---------------------------- | --------------------------------------------------
| `api/v2/auth/single`         | Fetch an IP-address-limited auth token

#### Query Parameters

| Parameter    | Notes
| ------------ | -----------------------------------------------------------------
| `username`   | The name of the user for whom the token is being requested.
| `password`   | The password of the user for whom the token is being requested.

The call will return either an auth token of the email and password match those of a 
user in the database.  The auth token will only be valid for connecting from the IP
address that made the api request.

#### Example

URL: http://www.mediacloud.org/api/v2/auth/single?username=foo&password=bar

Response:

```json
[
  {
    "result": "found",
    "token": "3827b988b309f8296fb47c0dbdd65302143f931c3852fdcb9083134ae6345f68"
   }
]
```

URL: http://www.mediacloud.org/api/v2/auth/single?username=foo&password=foobar

Response:

```json
[
  {
    "result": "not found"
   }
]
```


# Extended Examples

## Output Format / JSON
  
The format of the API responses is determined by the `Accept` header on the request. The default is `application/json`. Other supported formats include `text/html`, `text/x-json`, and `text/x-php-serialization`. It's recommended that you explicitly set the `Accept` header rather than relying on the default.
 
Here's an example of setting the `Accept` header in Python:

```python  
import pkg_resources  

import requests   
assert pkg_resources.get_distribution("requests").version >= '1.2.3'
 
r = requests.get( 'http://www.mediacloud.org/api/stories/all_processed?last_processed_stories_id=1', auth=('mediacloud-admin', KEY), headers = { 'Accept': 'application/json'})  

data = r.json()
```

## Create a CSV file with all media sources.

```python
media = []
start = 0
rows  = 100
while True:
      params = { 'start': start, 'rows': rows }
      print "start:{} rows:{}".format( start, rows)
      r = requests.get( 'http://www.mediacloud.org/api/v2/media/list', params = params, headers = { 'Accept': 'application/json'} )
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

## Grab all processed stories from US Top 25 MSM as a stream

This is broken down into multiple steps for convenience and because that's probably how a real user would do it. 

### Find the media set

We assume that the user is new to Media Cloud. They're interested in what sources we have available. They run cURL to get a quick list of the available dashboards.

```
curl http://www.mediacloud.org/api/v2/dashboards/list&nested_data=0
```

```json
[
 {"dashboards_id":1,"name":"US / English"}
 {"dashboards_id":2,"name":"Russia"}
 {"dashboards_id":3,"name":"test"}
 {"dashboards_id":5,"name":"Russia Full Morningside 2010"}
 {"dashboards_id":4,"name":"Russia Sampled Morningside 2010"}
 {"dashboards_id":6,"name":"US Miscellaneous"}
 {"dashboards_id":7,"name":"Nigeria"}
 {"dashboards_id":101,"name":"techblogs"}
 {"dashboards_id":116,"name":"US 2012 Election"}
 {"dashboards_id":247,"name":"Russian Public Sphere"}
 {"dashboards_id":463,"name":"lithanian"}
 {"dashboards_id":481,"name":"Korean"}
 {"dashboards_id":493,"name":"California"}
 {"dashboards_id":773,"name":"Egypt"}
]
```

The user sees the "US / English" dashboard with `dashboards_id = 1` and asks for more detailed information.

```
curl http://www.mediacloud.org/api/v2/dashboards/single/1
```

```json
[
   {
      "name":"US / English",
      "dashboards_id": "1",
      "media_sets":
      [
         {
      	 "media_sets_id":1,
	 "name":"Top 25 Mainstream Media",
	 "description":"Top 25 mainstream media sources by monthly unique users from the U.S. according to the Google AdPlanner service.",
	 media:
	   [
	     NOT SHOWN FOR SPACE REASONS 
	   ]
	 },
   	 {
	 "media_sets_id":26,
	 "name":"Popular Blogs",
	 "description":"1000 most popular feeds in bloglines.",
	  media:
	   [
	     NOT SHOWN FOR SPACE REASONS 
	   ]
   	   }
   ]  
]
```

*Note:* the full list of media are not shown for space reasons.

After looking at this output, the user decides that she is interested in the "Top 25 Mainstream Media" set with `media_sets_id=1`.

### Grab stories by querying stories/list

We can obtain all stories by repeatedly querying api/v2/stories/list using the `q` parameter to restrict to `media_sets_id = 1` and changing the `last_processed_stories_id` parameter. 

This is shown in the Python code below where `process_stories` is a user provided function to process this data.

```python
import requests

start = 0
rows  = 100
while True:
      params = { 'last_processed_stories_id': start, 'rows': rows, 'q': 'media_sets_id:1' }

      print "Fetching {} stories starting from {}".format( rows, start)
      r = requests.get( 'http://www.mediacloud.org/api/v2/stories/list/', params = params, headers = { 'Accept': 'application/json'} )
      stories = r.json()

      if len(stories) == 0:
      	 break

      start = stories[ -1 ][ 'processed_stories_id' ]

      process_stories( stories )
```


## Grab all stories in The New York Times during October 2012

### Find the `media_id` of The New York Times

Currently, the best way to do this is to create a CSV file with all media sources as shown in the earlier example.

Once you have this CSV file, manually search for The New York Times. You should find an entry for The New York Times at the top of the file with `media_id = 1`.

### Grab stories by querying stories/list

We can obtain the desired stories by repeatedly querying `api/v2/stories/list` using the `q` parameter to restrict to `media_id` to 1 and  the `fq` parameter to restrict by date range. We repeatedly change the `last_processed_stories_id` parameter to obtain all stories.

This is shown in the Python code below where `process_stories` is a user provided function to process this data.

```python
import requests

start = 0
rows  = 100
while True:
      params = { 'last_processed_stories_id': start, 
      'rows': rows, 'q': 'media_set_id:1', 'fq': 'publish_date:[2010-10-01T00:00:00Z TO 2010-11-01T00:00:00Z]'  }

      print "Fetching {} stories starting from {}".format( rows, start)
      r = requests.get( 'http://www.mediacloud.org/api/v2/stories/list/', params = params, headers = { 'Accept': 'application/json'} )
      stories = r.json()

      if len(stories) == 0:
      	 break

      start = stories[ -1 ][ 'processed_stories_id' ]

      process_stories( stories )
```

## Get word counts for top words for sentences matching 'trayvon' in U.S. Political Blogs during April 2012

This is broken down into multiple steps for convenience and because that's probably how a real user would do it. 


### Find the media set

We assume that the user is new to Media Cloud. They're interested in what sources we have available. They run cURL to get a quick list of the available dashboards.

```
curl http://www.mediacloud.org/api/v2/dashboards/list&nested_data=0
```

```json
[
 {"dashboards_id":1,"name":"US / English"}
 {"dashboards_id":2,"name":"Russia"}
 {"dashboards_id":3,"name":"test"}
 {"dashboards_id":5,"name":"Russia Full Morningside 2010"}
 {"dashboards_id":4,"name":"Russia Sampled Morningside 2010"}
 {"dashboards_id":6,"name":"US Miscellaneous"}
 {"dashboards_id":7,"name":"Nigeria"}
 {"dashboards_id":101,"name":"techblogs"}
 {"dashboards_id":116,"name":"US 2012 Election"}
 {"dashboards_id":247,"name":"Russian Public Sphere"}
 {"dashboards_id":463,"name":"lithanian"}
 {"dashboards_id":481,"name":"Korean"}
 {"dashboards_id":493,"name":"California"}
 {"dashboards_id":773,"name":"Egypt"}
]
```

The user sees the "US / English" dashboard with `dashboards_id = 1` and asks for more detailed information.

```
curl http://www.mediacloud.org/api/v2/dashboards/single/1
```

```json
[
   {
      "name":"dashboard 2",
      "dashboards_id": "2",
      "media_sets":
      [
         {
      	 "media_sets_id":1,
	 "name":"Top 25 Mainstream Media",
	 "description":"Top 25 mainstream media sources by monthly unique users from the U.S. according to the Google AdPlanner service.",
	 media:
	   [
	     NOT SHOWN FOR SPACE REASONS 
	   ]
	 },
   	 {
	 "media_sets_id":26,
	 "name":"Popular Blogs",
	 "description":"1000 most popular feeds in bloglines.",
	  "media":
	   [
	     NOT SHOWN FOR SPACE REASONS 
	   ]
   	 },
	 {
	     "media_sets_id": 7125,
             "name": "Political Blogs",
	     "description": "1000 most influential U.S. political blogs according to Technorati, pruned of mainstream media sources.",
	     "media":
	   [
	     NOT SHOWN FOR SPACE REASONS 
	   ]

	  }
   ]  
]
```

*Note:* the full list of media are not shown for space reasons.

After looking at this output, the user decides that she is interested in the "Political Blogs" set with `media_sets_id = 7125`.


### Make a request for the word counts based on `media_sets_id`, sentence text and date range

One way to appropriately restrict the data is by setting the `q` parameter to restrict by sentence content and then the `fq` parameter twice to restrict by `media_sets_id` and `publish_date`.

Below `q` is set to `"sentence:trayvon"` and `fq` is set to `"media_sets_id:7125" and "publish_date:[2012-04-01T00:00:00.000Z TO 2013-05-01T00:00:00.000Z]"`. (Note that ":", "[", and "]" are URL encoded.)

```
curl 'http://www.mediacloud.org/api/v2/wc?q=sentence:trayvon&fq=media_sets_id:7125&fq=publish_date:%5B2012-04-01T00:00:00.000Z+TO+2013-05-01T00:00:00.000Z%5D'
```

Alternatively, we could use a single large query by setting `q` to `"sentence:trayvon AND media_sets_id:7125 AND publish_date:[2012-04-01T00:00:00.000Z TO 2013-05-01T00:00:00.000Z]"`:

```
curl 'http://www.mediacloud.org/api/v2/wc?q=sentence:trayvon+AND+media_sets_id:7125+AND+publish_date:%5B2012-04-01T00:00:00.000Z+TO+2013-05-01T00:00:00.000Z%5D&fq=media_sets_id:7135&fq=publish_date:%5B2012-04-01T00:00:00.000Z+TO+2013-05-01T00:00:00.000Z%5D'
```


## Tag sentences of a story based on whether they have an odd or even number of characters

For simplicity, we assume that the user is interested in the story with `stories_id = 100` and is using a tag set called `'ts'`.

```python

stories_id = 100
r = requests.get( 'http://www.mediacloud.org/api/v2/story/single/' + stories_id, headers = { 'Accept': 'application/json'} )
data = r.json()
story = data[0]

custom_tags = []
tag_set_name = 'ts'
for story_sentence in story['story_sentences']:
    sentence_length = len( story_sentence['sentence'] )
    story_sentences_id = story_sentence[ 'story_sentences_id' ]

    if sentence_length %2 == 0:
       tag_name = 'even'
    else:
       tag_name = 'odd'

    custom_tags.append( '{},{}:{}'.format( story_sentences_id, tag_set_name, tag_name )


r = requests.put( 'http://www.mediacloud.org/api/v2/sentences/put_tags/', { 'sentence_tag': custom_tags }, headers = { 'Accept': 'application/json'} )  

```

## Get word counts for top words for sentences with the tag `'odd'` in `tag_set = 'ts'`


###Find the `tag_sets_id` for `'ts'`

The user requests a list of all tag sets.

```
curl http://www.mediacloud.org/api/v2/tag_sets/list
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
      params = { 'last_tags_id': last_tags_id, 'rows': rows }
      print "start:{} rows:{}".format( start, rows)
      r = requests.get( 'http://www.mediacloud.org/api/v2/tags/list/' + tag_sets_id , params = params, headers = { 'Accept': 'application/json'} )
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

Assume that the user determined that the `tags_id` was 12345678 using the above code.

```
curl 'http://www.mediacloud.org/api/v2/wc?q=tags:12345678'
```

## Grab stories from 10 January 2014 with the tag `'foo:bar'`

### Find the `tag_sets_id` for `'foo'`

See the "Get Word Counts for Top Words for Sentences with the Tag `'odd'` in `tag_set = 'ts'`" example above.

### Find the `tags_id` for `'bar'` given the `tag_sets_id`

See the "Get Word Counts for Top Words for Sentences with the Tag `'odd'` in `tag_set = 'ts'`" example above.

### Grab stories by querying stories/list

We assume the `tags_id` is 678910.

```
import requests

start = 0
rows  = 100
while True:
      params = { 'last_processed_stories_id': start, 'rows': rows, 'q': 'tags_id_stories:678910' }

      print "Fetching {} stories starting from {}".format( rows, start)
      r = requests.get( 'http://www.mediacloud.org/api/v2/stories/list/', params = params, headers = { 'Accept': 'application/json'} )
      stories = r.json()

      if len(stories) == 0:
         break

      start = stories[ -1 ][ 'processed_stories_id' ]

      process_stories( stories )
```
