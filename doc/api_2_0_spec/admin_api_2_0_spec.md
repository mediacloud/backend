% Media Cloud API Version 2
%

#API URLs

## Authentication

This document describes API calls for administrative users. These calls are intended for users running their own install of Media Cloud.
Users of the mediacloud.org API should refer instead to the Media Cloud API 2.0 Spec.

Please refer to the Media Cloud Api spec for general information on how requests should be constructed. 
Because the functionality of the admin api is largely a superset of the regular API, we do not include duplicative information in that document.

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
name will be created by the current user.  If the tag does not exist, a new tag will be created 
within the given tag set.

A user may only write put tags (or create new tags) within a tag set for which they have permission.

#### Example

Add tag ID 5678 to story ID 1234.

```
curl -X PUT -d story_tag=1234,5678 http://api.mediacloud.org/api/v2/stories/put_tags
```

Add the `gv_country:japan` and the `gv_country:brazil` tags to story 1234 and the `gv_country:japan` tag to 
story 5678.

```
curl -X PUT -d story_tag=1234,gv_country:japan -d story_tag=1234,gv_country:brazil -d story_tag=5678,gv_country:japan http://api.mediacloud.org/api/v2/stories/put_tags
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
curl -X PUT -d sentence_tag=12345678,gv_country:japan -d sentence_tag=12345678,gv_country:brazil -d sentence_tag=56781234,gv_country:japan http://api.mediacloud.org/api/v2/sentences/put_tags
```

### api/v2/tags/update (PUT)

| URL                                  | Function
| ------------------------------------ | -----------------------------------------------------------
| `api/v2/tags/update/<tags_id`        | Alter the tag in which `tags_id` equals `<tags_id>`

#### Query Parameters 

| Parameter            | Notes
| -------------------- | --------------------------------------------------------------------------
| `tag`                | New name for the tag.
| `label`              | New label for the tag.
| `description`        | New description for the tag.

#### Example

```
curl -X PUT -d 'tag=test_tagXX' -d 'label=YY' -d 'description=Bfoo' http://api.mediacloud.org/api/v2/tags/update/23
```

### api/v2/tag_sets/update (PUT)

| URL                                   | Function
| ------------------------------------  | -----------------------------------------------------------
| `api/v2/tag_sets/update/<tag_sets_id` | Alter the tag set in which `tag_sets_id` equals `<tag_sets_id>`

#### Query Parameters 

| Parameter            | Notes
| -------------------- | --------------------------------------------------------------------------
| `name`               | New name for the tag set.
| `label`              | New label for the tag set.
| `description`        | New description for the tag set.

#### Example

```
curl -X PUT -d 'name=collection' -d 'label=XXXX' -d 'description=foo' http://api.mediacloud.org/api/v2/tag_sets/update/1
```

### Tag Set Permissions

Within the administrative backend users are granted permissions at the tag set level.
For each tag set a users may have up to 4 of the following permissions: edit_tag_descriptors, edit_tag_descriptors, appy_tags, and create_tags.

These permissions are described below:

| Parameter                   | Notes
| --------------------        | --------------------------------------------------------------------------
| ` edit_tag_descriptors`     | For all tags in the tag set, the user may alter the tag name, tag description, and tag label using the api/v2/tags/update API call
| ` edit_tag_set_descriptors` | The user may alter the tag set name, tag set description, and tag  set label for the tag set using the api/v2/tag_sets/update API call
| `apply_tags`                | The user may apply existing tags within the tag set to stories and sentences
| `create_tags`               | The user may create new tags within the tag set


#### Granting Permissions

Tag set permissions must be explicitly granted to users in the administrative backend UI. 
To grant user permissions go to  https://core.mediacloud.org/admin/users/list and click the Edit Tag Set Permissions link for that user.

Do to the importance of tags and the potential for confusion and accidential misuse, permissions must be explicitly granted on a per user basis by administrators. With the exception of user name tag sets (see below), the default is for users to have no tag set permissions that have not been explicitly granted.

#### Exceptions - user name tag sets

If the name of the tag_set matches the user's email address, they will be granted all 4 of the permissions above for that tag set.  For example, a user with the email address jdoe@mediacloud.org would be able to 

Note that this exception is based purely on a string comparison of the tag set name with the user's email. Thus if a user creates a tag set that matched their email address, they will be able to alter this tag set and its tags. However, if the user changes the name of the tag_set, through a call to api/v2/tag_sets/update, so that it no longer matches their email address, they will no longer have permissions for this tag set unless they have been explicitly given access in the administrative backend.

