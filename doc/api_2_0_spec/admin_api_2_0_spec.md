% Media Cloud API Version 2
%

#API URLs

*Note:* by default the API only returns a subset of the available fields in returned objects. The returned fields are those that we consider to be the most relevant to users of the API. If the `all_fields` parameter is provided and is non-zero, then a more complete list of fields will be returned. For space reasons, we do not list the `all_fields` parameter on individual API descriptions.

## Authentication

This document describes API calls for administrative users. These calls are intended for users running their own install of Media Cloud.

Please refer to the Media Cloud Api spec for general information on how requests should be constructed. 
Because the functionality of the admin api is largely a superset of the regular API, we do not include duplicative information in this document.


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

