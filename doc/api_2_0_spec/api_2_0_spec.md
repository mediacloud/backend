Media Cloud API Version 2
=========================

**Author:** David Larochelle


API URLs
--------

*Note:* by default the API only returns a subset of the available fields in returned objects. The returned fields are those that we consider to be the most relevant to users of the API. If the `all_fields` parameter is provided and is non-zero, then a most complete list of fields will be returned. For space reasons, we do not list the `all_fields` parameter on individual API descriptions.

### Media

#### api/v2/media/single/

| URL                              | Function
| -------------------------------- | -------------------------------------------------------------
| `api/v2/media/single/<media_id>` | Return the media source in which media_id equals `<media_id>`

##### Query Parameters 

None.

##### Example

Fetching information on the New York Times

URL: http://mediacloud.org/api/v2/media/single/1

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


#### api/v2/media/list/

| URL                 | Function
| ------------------- | -----------------------------
| `api/v2/media/list` | Return multiple media sources

##### Query Parameters 

| Parameter       | Default | Notes
| --------------- | ------- | -----------------------------------------------------------------
| `last_media_id` | 0       | Return media sources with a `media_id` is greater than this value
| `rows`          | 20      | Number of media sources to return. Cannot be larger than 100

##### Example

URL: http://mediacloud.org/api/v2/media/list?last_media_id=1&rows=2

```json
[
    "name": "Washington Post",
    "url": "http:\/\/washingtonpost.com",
    "media_id": 2,
  {
    "media_sets": [
      {
        "description": null,
        "name": "Washington Post",
        "media_sets_id": 18,
        "set_type": "medium"
      }
    ],
    "media_source_tags": [
      {
        "tags_id": 1,
        "tag": "newspapers",
        "tag_sets_id": 1,
        "tag_set": "media_type"
      },
      {
        "tag_set": "workflow",
        "tag_sets_id": 4,
        "tag": "pmcheck",
        "tags_id": 6
      },
      {
        "tag": "hrcheck",
        "tags_id": 7,
        "tag_set": "workflow",
        "tag_sets_id": 4
      },
      {
        "tag": "7",
        "tags_id": 18,
        "tag_set": "usnewspapercirculation",
        "tag_sets_id": 3
      },
      {
        "tags_id": 6071565,
        "tag": "include",
        "tag_set": "word_cloud",
        "tag_sets_id": 17
      },
      {
        "tag_sets_id": 17,
        "tag_set": "word_cloud",
        "tag": "default",
        "tags_id": 6729599
      },
      {
        "tags_id": 8875027,
        "tag": "ap_english_us_top25_20100110",
        "tag_set": "collection",
        "tag_sets_id": 5
      }
    ]
  },
  {
    "url": "http:\/\/csmonitor.com",
    "media_id": 3,
    "media_sets": [
      
    ],
    "name": "Christian Science Monitor",
    "media_source_tags": [
      {
        "tag_sets_id": 1,
        "tag_set": "media_type",
        "tags_id": 1,
        "tag": "newspapers"
      },
      {
        "tag": "needs",
        "tags_id": 110,
        "tag_sets_id": 4,
        "tag_set": "workflow"
      },
      {
        "tag_set": "workflow",
        "tag_sets_id": 4,
        "tags_id": 111,
        "tag": "collection"
      }
    ]
  }
]
```

### Media Sets

#### api/v2/media_set/single

| URL                                       | Function
| ----------------------------------------- | ----------------------------------------------------------------------
| `api/v2/media_set/single/<media_sets_id>` | Return the media set in which `media_sets_id` equals `<media_sets_id>`

##### Query Parameters

None.

##### Example

http://mediacloud.org/api/v2/media_sets/single/2

```json
[
   {
     "name": "set name",
     "media_sets_id": 2,
     "description": "media_set 2 description",
     "media": 
     [
      	    {       "name": "source 1 name",
	            "media_id": "source 1 media id",
		    "url": "http://source1.com"
            },
      	    {       "name": "source 2 name",
	            "media_id": "source 2 media id",
		    "url": "http://source2.com"
            },
     ]
   }
]
```

#### api/v2/media_sets/list

| URL                      | Function
| ------------------------ | --------------------------
| `api/v2/media_sets/list` | Return multiple media sets

##### Query Parameters 

| Parameter            | Default | Notes
| -------------------- | ------- | -----------------------------------------------------------------
| `last_media_sets_id` | 0       | Return media sets with `media_sets_id` is greater than this value
| `rows`               | 20      | Number of media sets to return. Cannot be larger than 100

##### Example

URL: http://mediacloud.org/api/v2/media_sets/list?rows=1&last_media_sets_id=1

```json
[
   {
     "name": "set name",
     "media_sets_id": "2",
     "description": "media_set 2 description",
     "media": 
     [
      	    {       "name": "source 1 name",
	            "media_id": "source 1 media id",
		    "url": "http://source1.com"
            },
      	    {       "name": "source 2 name",
	            "media_id": "source 2 media id",
		    "url": "http://source2.com"
            },
     ]
   }
]
```

### Feeds

#### api/v2/feeds/single

| URL                              | Function
| -------------------------------- | --------------------------------------------------------
| `api/v2/feeds/single/<feeds_id>` | Return the feeds in which `feeds_id` equals `<feeds_id>`

##### Query Parameters 

None.

##### Example

URL: http://mediacloud.org/api/v2/feeds/single/1

```json
[
  {
    "name": "Bits",
    "url": "http:\/\/bits.blogs.nytimes.com\/rss2.xml",
    "feeds_id": 1,
    "feed_type": "syndicated",
    "feed_status": "active",
    "media_id": 1
  }
]
```

#### api/v2/feeds/list

| URL                 | Function
| ------------------- | --------------------------
| `api/v2/feeds/list` | Return multiple media sets

##### Query Parameters

| Parameter       | Default | Notes
| --------------- | ------- | -------------------------------------------------------
| `last_feeds_id` | 0       | Return feeds with `feeds_id` is greater than this value
| `rows`          | 20      | Number of feeds to return. Cannot be larger than 100

##### Example

URL: http://mediacloud.org/api/v2/feeds/list?rows=1&last_feeds_id=1

```json
[
  {
    "name": "DealBook",
    "url": "http:\/\/dealbook.blogs.nytimes.com\/rss2.xml",
    "feeds_id": 2,
    "feed_type": "syndicated",
    "feed_status": "active",
    "media_id": 1
  },
  {
    "name": "Essential Knowledge of the Day",
    "url": "http:\/\/feeds.feedburner.com\/essentialknowledge",
    "feeds_id": 3,
    "feed_type": "syndicated",
    "feed_status": "active",
    "media_id": 1
  }
]
```

### Dashboards

#### api/v2/dashboard/single

| URL                                       | Function
| ----------------------------------------- | ----------------------------------------------------------------------
| `api/v2/dashboard/single/<dashboards_id>` | Return the dashboard in which `dashboards_id` equals `<dashboards_id>`

##### Query Parameters 

| Parameter     | Default | Notes
| ------------- | ------- | -------------------------------------------------------------------------------------
| `nested_data` | 1       | If 0, return only the `name` and `dashboards_id`.<br />If 1, return nested information about the dashboard's `media_sets` and their `media`.

##### Example

http://mediacloud.org/api/v2/dashboards/single/2

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

#### api/v2/dashboards/list

| URL                      | Function
| ------------------------ | --------------------------
| `api/v2/dashboards/list` | Return multiple dashboards

##### Query Parameters 

| Parameter            | Default | Notes
| -------------------- | ------- | -------------------------------------------------------------------------------------
| `last_dashboards_id` | 0       | Return dashboards in which `dashboards_id` greater than this value
| `rows`               | 20      | Number of dashboards to return. Can not be larger than 100
| `nested_data`        | 1       | If 0, return only the `name` and `dashboards_id`.<br />If 1, return nested information about the dashboard's `media_sets` and their `media`.

##### Example

URL: http://mediacloud.org/api/v2/dashboards/list?rows=1&last_dashboards_id=1

```json
[
   {
      "name":"dashboard 2",
      "dashboards_id":2,
      "media_sets":
      [
      {
         "name":"set name",
         "media_sets_id":2,
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

### Stories

#### Output description

The following table describes the meaning and origin of fields returned by both api/v2/stories/single and api/v2/stories/list_processed in which we felt clarification was necessary.

| Field               | Description
| ------------------- | ----------------------------------------------------------------------
| `title`             | The story title as defined in the RSS feed. May contain HTML (depending on the source).
| `description`       | The story description as defined in the RSS feed. May contain HTML (depending on the source).
| `full_text_rss`     | If 1, the text of the story was obtained through the RSS feed.<br />If 0, the text of the story was obtained by extracting the article text from the HTML.
| `story_text`        | The text of the story.<br />If `full_text_rss` is non-zero, this is formed by stripping HTML from the title, description, and concatenating them.<br />If `full_text_rss` is zero, this is formed by extracting the article text from the HTML.
| `story_sentences`   | A list of sentences in the story.<br />Generated from `story_text` by splitting it into sentences and removing any duplicate sentences occurring within the same source for the same week.
| `raw_1st_download`  | The contents of the first HTML page of the story.<br />Available regards of the value of `full_text_rss`.<br />*Note:* only provided if the `raw_1st_download` parameter is non-zero.
| `publish_date`      | The publish date of the story as specified in the RSS feed.
| `custom_story_tags` | A list containing the names of any tags that have been added to the story using the write-back API.
| `collect_date`      | The date the RSS feed was actually downloaded.
| `guid`              | The GUID field in the RSS feed. Defaults to the URL if no GUID is specified.


#### api/v2/stories/single

| URL                                  | Function
| ------------------------------------ | ------------------------------------------------------
| `api/v2/stories/single/<stories_id>` | Return story in which stories_id equals `<stories_id>`

##### Query Parameters 

| Parameter          | Default | Notes
| ------------------ | ------- | -----------------------------------------------------------------
| `raw_1st_download` | 0       | If non-zero, include the full html of the first page of the story

##### Example

Note: This fetches data on the CC licensed Global Voices Story ["Myanmar's new flag and new name"](http://globalvoicesonline.org/2010/10/26/myanmars-new-flag-and-new-name/#comment-1733161) from November 2010.

URL: http://mediacloud.org/api/v2/stories/single/27456565


```json
[
  {
    "db_row_last_updated": null,
    "full_text_rss": 0,
    "description": "<p>Both the previously current and now current Burmese flags look ugly and ridiculous!  Burma once had a flag that was actually better looking.  Also Taiwan&#8217;s flag needs to change!  it is a party state flag representing the republic of china since 1911 and Taiwan\/Formosa was Japanese colony since 1895.  A new flag representing the land, people and history of Taiwan needs to be given birth to and flown!<\/p>\n",
    "language": null,
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
    "custom_story_tags": [
       "custom_tag_1",
       "custom_tag_2"
    ],
    "story_sentences": [
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "Myanmar's new flag and new name The new flag, designated in the 2008 Constitution, has a central star set against a yellow, green and red background.",
        "sentence_number": 0,
        "story_sentences_id": "525687757",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00"
      },
      {
        "sentence_number": 1,
        "story_sentences_id": "525687758",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "language": null,
        "db_row_last_updated": null,
        "sentence": "The old flags will be lowered by government department officials who were born on a Tuesday, while the new flags will be raised by officials born on a Wednesday."
      },
      // SENTENCES SKIPPED BECAUSE OF SPACE REASONS
      {
        "language": null,
        "db_row_last_updated": null,
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
        "language": null
      }
    ],
    "story_tags": [
      
    ],
  }
]
```

#### api/V2/stories/list_processed 
  
To get information on multiple stories, send get requests to `api/V2/stories/list_processed`

| URL                             | Function
| ------------------------------- | ---------------------------------
| `api/V2/stories/list_processed` | Return multiple processed stories

##### Query Parameters 

| Parameter                    | Default | Notes
| ---------------------------- | ------- | ------------------------------------------------------------------------------
| `last_processed_stories_id`  | 0       | Return stories in which the `processed_stories_id` is greater than this value.
| `rows`                       | 20      | Number of stories to return. Can not be larger than 100.
| `raw_1st_download`           | 0       | If non-zero, include the full HTML of the first page of the story.

The `last_processed_id` parameter can be used to page through these results. The API will return 20 stories with a `processed_id` greater than this value.

*Note:* `stories_id` and `processed_id` are separate values. The order in which stories are processed is different than the `stories_id` order. The processing pipeline involves downloading, extracting, and vectoring stories. Since unprocessed stories are of little interest, we have introduced the `processed_id` field to allow users to stream all stories as they're processed.

##### Example

URL: http://mediacloud.org/api/v2/stories/list_processed/&last_processed_stories_id=86259158&rows=1

```json
[
  {
    "processed_stories_id": "86259159",
    "story_text": " \t\t\t\t\t\tMyanmar's new flag and new name\t\t    The new flag, designated in the 2008 Constitution, has a central star set against a yellow, green and red background.   The old flags will be lowered by government department officials who were born on a Tuesday, while the new flags will be raised by officials born on a Wednesday.   <SENTENCES SKIPPED BECAUSE OF SPACE REASONS> You know That big white star is also the only star on the colors of Myanmar's tatmadaw, navy, air force and police force. This flag represent only the armed forces.  ",
    "guid": "http:\/\/globalvoicesonline.org\/?p=169660#comment-1733161",
    "publish_date": "2010-11-24 04:05:00",
    "media_id": 1144,
    "stories_id": 27456565,
    "story_texts_id": null,
    "story_sentences": [
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "Myanmar's new flag and new name The new flag, designated in the 2008 Constitution, has a central star set against a yellow, green and red background.",
        "sentence_number": 0,
        "story_sentences_id": "525687757",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00"
      },
      {
        "sentence_number": 1,
        "story_sentences_id": "525687758",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "language": null,
        "db_row_last_updated": null,
        "sentence": "The old flags will be lowered by government department officials who were born on a Tuesday, while the new flags will be raised by officials born on a Wednesday."
      },
      // SENTENCES SKIPPED BECAUSE OF SPACE REASONS
      {
        "language": null,
        "db_row_last_updated": null,
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
        "language": null
      }
    ],
    "db_row_last_updated": null,
    "story_tags": [
      
    ],
    "full_text_rss": 0,
    "description": "<p>Both the previously current and now current Burmese flags look ugly and ridiculous!  Burma once had a flag that was actually better looking.  Also Taiwan&#8217;s flag needs to change!  it is a party state flag representing the republic of china since 1911 and Taiwan\/Formosa was Japanese colony since 1895.  A new flag representing the land, people and history of Taiwan needs to be given birth to and flown!<\/p>\n",
    "language": null,
    "title": "Comment on Myanmar's new flag and new name by kc",
    "fully_extracted": 1,
    "collect_date": "2010-11-24 15:33:39",
    "url": "http:\/\/globalvoicesonline.org\/2010\/10\/26\/myanmars-new-flag-and-new-name\/comment-page-1\/#comment-1733161"
  }
]
```

###  Story subsets

Users who want to only see a subset of stories can create a story subset stream by sending a put request to `api/v2/stories/subset/`.

#### api/v2/stories/subset (PUT)

| URL                     | Function
| ----------------------- | -----------------------------------------------
| `api/v2/stories/subset` | Creates a story subset. Must use a PUT request.

##### Query Parameters 

| Parameter          | Notes
| ------------------ | ----------------------------------------------------------------------------------
| `start_date`       | Only include stories with a `publish date >= start_date`
| `end_date`         | Only include stories with a `publish date <= end_date`
| `media_id`         | Only include stories from the media source indicated by `media_id`
| `media_sets_id`    | Only include stories from the media set indicated by `media_sets_id`
| `custom_story_tag` | Only include stories in which `custom_story_tag` in one of the `custom_story_tags`

*Note:* At least one of the above parameters must by provided.

The put request will return the meta-data representation of the `story_subset` including its database ID.
  
It will take the backend system a while to generate the stream of stories for the newly created subset. There is a background daemon script (`mediawords_process_story_subsets.pl`) that detects newly created subsets and adds stories to them.

##### Example

Create a story subset for the New York Times from January 1, 2014 to January 2, 2014

```
curl -X PUT -d media_id=1 -d start_date=2014-01-01 -d end_date=2014-01-02 http://mediacloud.org/api/v2/stories/subset
```

```json
{
   "media_id":1,
   "end_date":"2014-01-02 00:00:00-00",
   "media_sets_id":null,
   "start_date":"2014-01-01 00:00:00-00",
   "ready":0,
   "custom_story_tag": null,
   "story_subsets_id":"1"
}
```

#### api/v2/stories/subset (GET)

| URL                     | Function
| ----------------------- | ----------------------------------------------------
| `api/v2/stories/subset` | Show the status of a subset. Must use a GET request.

To see the status of a given subset, the client sends a get request to `api/v2/stories/subset/<ID>` where `<ID>` is the database id that was returned in the put request above. **The returned object contains a `ready` field with a Boolean value indicating that stories from the subset have been compiled.**

##### Example 

curl -X GET http://0:3000/api/v2/stories/subset/1

```json
{
   "media_id":1,
   "end_date":"2013-01-02 00:00:00-05",
   "media_sets_id":null,
   "start_date":"2013-01-01 00:00:00-05",
   "last_processed_stories_id":"116335917",
   "custom_story_tag": null,
   "ready":1,
   "story_subsets_id":"1"
}
```
 
#### api/v2/stories/list_subset_processed

| URL                                         | Function
| ------------------------------------------- | --------------------------------------------------------------------------------
| `api/v2/stories/list_subset_processed/<id>` | Return multiple processed stories from a subset. `<id>` is the id of the subset.

##### Query Parameters

| Parameter                   | Default | Notes
| --------------------------- | ------- | ------------------------------------------------------------------------------
| `last_processed_stories_id` | 0       | Return stories in which the `processed_stories_id` is greater than this value.
| `rows`                      | 20      | Number of stories to return. Cannot be larger than 100.
| `raw_1st_download`          | 0       | If non-zero, include the full HTML of the first page of the story.

This behaves similarly to the `list_processed` URL above except only stories from the given subset are returned.

### Solr

#### api/v2/solr/sentences

##### Query Parameters

| Parameter | Default | Notes
| --------- | ------- | ----------------------------------------------------------------
| `q`       | n/a     | `q` ("query") parameter which is passed directly to Solr
| `fq`      | `null`  | `fq` ("filter query") parameter which is passed directly to Solr
| `start`   | 0       | Passed directly to Solr
| `rows`    | 1000    | Passed directly to Solr

--------------------------------------------------------------------------------------------------------

See the [Solr documentation](http://wiki.apache.org/solr/CommonQueryParameters) for a detailed description of these 4 parameters.

##### Example

Fetch 10 sentences containing the word 'obama' from the New York Times

URL:  http://mediacloud.org/api/v2/solr/sentences?q=sentence%3Aobama&rows=10&fq=media_id%3A1

```json
[
  {
    "id": "959545252_ss",
    "field_type": "ss",
    "publish_date": "2012-04-18T16:10:06Z",
    "media_id": 1,
    "story_sentences_id": "959545252",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "Obama:",
    "sentence_number": 16,
    "stories_id": 79115414,
    "custom_story_tags": [
      "custom_tag_1",
      "custom_tag_2"
    ],
    "custom_sentence_tags": [
      "custom_tag_A",
      "custom_tag_B"
    ],
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "tags_id_stories": [
      8878051,
      8878085
    ],
    "_version_": 1.4579959345877e+18
  },
  {
    "id": "816034983_ss",
    "field_type": "ss",
    "publish_date": "2011-10-04T09:15:23Z",
    "media_id": 1,
    "story_sentences_id": "816034983",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "Obama!",
    "sentence_number": 8,
    "stories_id": 42553267,
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "_version_": 1.4580934893476e+18
  },
  // <...> -- sentences skipped for space reasons
  {
    "id": "915146557_ss",
    "field_type": "ss",
    "publish_date": "2010-11-03T04:18:40Z",
    "media_id": 1,
    "story_sentences_id": "915146557",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "OBAMA 3",
    "sentence_number": 12,
    "stories_id": 76521646,
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "_version_": 1.4580067639912e+18
  },
  {
    "id": "911745123_ss",
    "field_type": "ss",
    "publish_date": "2012-01-03T11:13:06Z",
    "media_id": 1,
    "story_sentences_id": "911745123",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "Obama bad.",
    "sentence_number": 46,
    "stories_id": 46771580,
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "_version_": 1.4580076258599e+18
  }
]
```

#### api/v2/solr/wc

##### Query Parameters

| Parameter | Default | Notes
| --------- | ------- | ----------------------------------------------------------------
| `q`       | n/a     | `q` ("query") parameter which is passed directly to Solr
| `fq`      | `null`  | `fq` ("filter query") parameter which is passed directly to Solr

Returns word frequency counts for all sentences returned by querying Solr using the `q` and `fq` parameters.

See the [Solr documentation](http://wiki.apache.org/solr/CommonQueryParameters) for a detailed description of `q` and `fq`.

#### Example

Obtain word frequency counts for all sentences containing the word 'obama' in the New York Times

URL:  http://mediacloud.org/api/v2/solr/wc?q=sentence%3Aobama&fq=media_id%3A1

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
  // WORDS SKIPPED BECAUSE OF SPACE REASONS
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


### Write Back API

These calls allow users to push data into the PostgreSQL database.

#### api/v2/stories/custom_tags (PUT)

| URL                          | Function
| ---------------------------- | --------------------------------------------------
| `api/v2/stories/custom_tags` | Add custom tags to a story. Must be a PUT request.

##### Query Parameters

| Parameter    | Notes
| ------------ | -----------------------------------------------------------------
| `stories_id` | The ID of the story to which to add the custom tags
| `custom_tag` | Can be specified multiple times to add multiple tags to the story

##### Example

Set `custom_story_tags` on the story with stories_id 1000 to 'foo' and 'bar'

```
curl -X PUT -d stories_id=10000 -d custom_tag=foo -d custom_tag=bar http://mediacloud.org/api/v2/stories/custom_tags
```


#### api/v2/story_sentences/custom_tags (PUT)

| URL                                  | Function
| ------------------------------------ | -----------------------------------------------------------
| `api/v2/story_sentences/custom_tags` | Add custom tags to a story sentence. Must be a PUT request.

##### Query Parameters 

| Parameter            | Notes
| -------------------- | --------------------------------------------------------------------------
| `story_sentences_id` | The ID of the story sentence to which to add the custom tags
| `custom_tag`         | Can be specified multiple times to add multiple tags to the story sentence

*Note:*  when a story is re-processed, its story sentence objects are deleted and recreated. In practice, it is rare for stories to be 
reprocessed. But if a story is reprocessed any custom tags attached to its story sentences will be lost. 
(Custom tags on the story itself will persist reprocessing.)

##### Example

Set the `custom_sentence_tags` on the story sentence with `story_sentences_id = 1000` to 'foo' and 'bar':

```
curl -X PUT -d stories_id=10000 -d custom_tag=foo -d custom_tag=bar http://mediacloud.org/api/v2/story_sentences/custom_tags
```


Extended Examples
-----------------

### Output Format / JSON
  
The format of the API responses is determined by the `Accept` header on the request. The default is `application/json`. Other supported formats include `text/html`, `text/x-json`, and `text/x-php-serialization`. It's recommended that you explicitly set the `Accept` header rather than relying on the default.
 
Here's an example of setting the `Accept` header in Python:

```python  
import pkg_resources  

import requests   
assert pkg_resources.get_distribution("requests").version >= '1.2.3'
 
r = requests.get( 'http://mediacloud.org/api/stories/all_processed?last_processed_stories_id=1', auth=('mediacloud-admin', KEY), headers = { 'Accept': 'application/json'})  

data = r.json()
```

### Create a CSV file with all media sources.

```python
media = []
start = 0
rows  = 100
while True:
      params = { 'start': start, 'rows': rows }
      print "start:{} rows:{}".format( start, rows)
      r = requests.get( 'http://mediacloud.org/api/v2/media/list', params = params, headers = { 'Accept': 'application/json'} )
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

### Grab all processed stories from US Top 25 MSM as a stream

This is broken down into multiple steps for convenience and because that's probably how a real user would do it. 

#### Find the media set

We assume that the user is new to Media Cloud. They're interested in what sources we have available. They run curl to get a quick list of the available dashboards.

```
curl http://mediacloud.org/api/v2/dashboards/list&nested_data=0
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
curl http://mediacloud.org/api/v2/dashboards/single/1
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

After looking at this output, the user decides that she is interested in the "Top 25 Mainstream Media" set with `media_id=1`.


#### Create a subset

```
curl -X PUT -d media_set_id=1 http://mediacloud.org/api/v2/stories/subset
```

Save the `story_subsets_id`.

### Wait until the subset is ready

Below we show some Python code to continuously poll the server to determine whether the subset has been processed. Users could do something similar manually by issuing curl requests.

```python
import requests
import time

while True:
    r = requests.get( 'http://mediacloud.org/api/v2/stories/subset/' + story_subsets_id, headers = { 'Accept': 'application/json'} )
    data = r.json()

    if data['ready'] == '1':
       break
    else:
       time.sleep 120

print "subset {} is ready".format( story_subsets_id )
```


#### Grab stories from the processed stream

Since the subset is now processed we can obtain all of its stories by repeatedly querying `list_subset_processed` and changing the `last_processed_stories_id` parameter. 

This is shown in the Python code below where `process_stories` is a user provided function to process this data.

```python
import requests

start = 0
rows  = 100
while True:
      params = { 'last_processed_stories_id': start, 'rows': rows }

      print "Fetching {} stories starting from {}".format( rows, start)
      r = requests.get( 'http://mediacloud.org/api/v2/stories/list_subset_processed/' +  story_subsets_id, params = params, headers = { 'Accept': 'application/json'} )
      stories = r.json()

      if len(stories) == 0:
      	 break

      start += rows

      process_stories( stories )
```


### Grab all stories in the New York Times during October 2012

#### Find the `media_id` of the New York Times

Currently, the best way to do this is to create a CSV file with all media sources as shown in the earlier example.

Once you have this CSV file, manually search for the New York Times. You should find an entry for the New York Times at the top of the file with `media_id = 1`.


#### Create a subset

```
curl -X PUT -d start_date=2012-10-01 -d end_date=2012-11-01 -d media_id=1 http://mediacloud.org/api/v2/stories/subset
```

Save the `story_subsets_id`.


#### Wait until the subset is ready

See the 25 msm example above.


#### Grab stories from the processed stream

See the 25 msm example above.


### Get word counts for top words for sentences matching 'trayvon' in U.S. Political Blogs during April 2012

This is broken down into multiple steps for convenience and because that's probably how a real user would do it. 


#### Find the media set

We assume that the user is new to Media Cloud. They're interested in what sources we have available. They run curl to get a quick list of the available dashboards.

```
curl http://mediacloud.org/api/v2/dashboards/list&nested_data=0
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
curl http://mediacloud.org/api/v2/dashboards/single/1
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

*Note:* the list of media are not shown for space reasons.

After looking at this output, the user decides that she is interested in the "Political Blogs" set with `media_id = 7125`.


#### Make a request for the word counts based on `media_sets_id` and sentence text and date range

One way to appropriately restrict the data is by setting the `q` parameter to restrict by sentence content and then the `fq` parameter twice to restrict by `media_sets_id` and `publish_date`.

Below `q` is set to "sentence:trayvon" and `fq` is set to "media_sets_id:7125" and "publish_date:[2012-04-01T00:00:00.000Z TO 2013-05-01T00:00:00.000Z]". (Note that ":", "[", and "]" are URL encoded.)

```
curl 'http://mediacloud.org/api/v2/solr/wc?q=sentence%3Atrayvon&fq=media_sets_id%3A7125&fq=publish_date%3A%5B2012-04-01T00%3A00%3A00.000Z+TO+2013-05-01T00%3A00%3A00.000Z%5D'
```

Alternatively, we could use a single large query by setting `q` to "sentence:trayvon AND media_sets_id:7125 AND publish_date:[2012-04-01T00:00:00.000Z TO 2013-05-01T00:00:00.000Z]":

```
curl 'http://mediacloud.org/api/v2/solr/wc?q=sentence%3Atrayvon+AND+media_sets_id%3A7125+AND+publish_date%3A%5B2012-04-01T00%3A00%3A00.000Z+TO+2013-05-01T00%3A00%3A00.000Z%5D&fq=media_sets_id%3A7135&fq=publish_date%3A%5B2012-04-01T00%3A00%3A00.000Z+TO+2013-05-01T00%3A00%3A00.000Z%5D'
```


### Tag sentences of a story based on whether they have an odd or even number of characters

For simplicity, we assume that the user is interested in the story with `stories_id = 100`:

```python

stories_id = 100
r = requests.get( 'http://mediacloud.org/api/v2/story/single/' + stories_id, headers = { 'Accept': 'application/json'} )
data = r.json()
story = data[0]

for story_sentence in story['story_sentences']:
    sentence_length = len( story_sentence['sentence'] )
    story_sentences_id = story_sentence[ 'story_sentences_id' ]

    custom_tags = set(story_sentence[ 'custom_tags' ])

    if sentence_length %2 == 0:
       custom_tags.append( 'odd' )
    else:
       custom_tags.append( 'even' )

    r = requests.put( 'http://mediacloud.org/api/v2/story_sentences/custom_tags/' + stories_id, { 'custom_tags': custom_tags}, headers = { 'Accept': 'application/json'} )  

```


### Get word counts for top words for sentences with the custom sentence tag 'odd'

#### Make a request for the word counts based on the custom sentence tag 'odd'

Below `q` is set to "custom_sentence_tag:odd". (Note that ":", "[", and "]" are URL encoded.)

```
curl 'http://mediacloud.org/api/v2/solr/wc?q=custom_sentence_tag%3Afoobar'
```


### Grab stories from 10 January 2014 with the custom tag 'foobar'

#### Create a subset

```
curl -X PUT -d start_date=2014-01-10 -d end_date=2014-01-11 -d custom_story_tag=foobar http://mediacloud.org/api/v2/stories/subset
```

Save the `story_subsets_id`.


#### Wait until the subset is ready

See the 25 msm example above.


#### Grab stories from the processed stream

See the 25 msm example above.
