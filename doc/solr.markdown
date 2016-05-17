Solr
====

Media Cloud uses solr as its text indexing and search engine.

The Media Cloud repo has a solr 4.6 distribution included within it in the solr/ directory.  For information on running
the solr engine, see the [hosting docs](hosting/solr-hosting.markdown).

We use sharding within solr to host the solr data across multiple server processes on each server and across
multiple servers.  Solr requires multiple shards in the same machine to take advantage of parallel processing
capabilities (including both multiple CPU cores and multiple disks) on the same machine.  The host docs referenced
above describe how we administer our solr cluster, including scripts we use to create, start, stop, and reload
solr shards.

The basic interaction between solr and the rest of the platform is that we import any updated story_sentences into
solr from the postgres server every hour by running an hourly cron script on the solr server.  The import script
knows which sentences to import by keep track of db_row_last_updated fields on the stories, media, and story_sentences
table.  The import script queries story_sentences for all distinct stories for which the db_row_last_updated value
is greater than the latest value in solr_imports.  Triggers in the postgres database update the
story_sentences.db_row_last_updated value on story_sentences whenever a related story, medium, story tag,
medium tag, or story sentence tag is updated.

The list of fields imported by solr is configured in
[solr/collection1/solr/conf/schema.xml](../solr/collection1/solr/conf/schema.xml).  As of this doc, we index the
following fields: story_sentences_id, media_id, stories_id, sentence_number, processed_stories_id, sentence, title,
publish_date, publish_day, language, bitly_cick_count, media_sets_id, tags_id_stories, tags_id_media,
tags_id_story_sentences.  

Of the above, only the following are stored fields (meaning they are returned by solr queries): story_sentences_id,
stories_id, processed_stories_id, sentence, title, bitly_click_count.  Storing fields in addition to indexing them
requires significant extra resources (disk space, import time, query time), so we should not store fields unless
there is a good reason for not just querying the results from postgres once we get the stories_ids back.  We
store the above fields for the following reason:

| Field | Reason |
------------------
| story_sentences_id | must look up the specific returned sentence |
| stories_id | must return grouped stories_id to efficiently search for lists of stories |
| processed_stories_id | must query postgres for returned stories_ids ordered by specific processed_stories_id |
| sentence | must get sentence back to efficiently count words without querying story_sentences |
| title | must get title back to efficiently count words |
| bitly_click_count | must get bitly_click_count to efficiently query without hitting large bitly_clicks_total table |

Titles are stored as separate documents.  So a story with ten sentences will be imported as 11 documents -- 10 documents
with the sentence field set and 1 with the title field set.

For the solr_id, we use '<stories_id>|<story_sentences_id>' (for example '1234|123456'), which allows solr to store
sentences from the same story on the same shard.  Sharding by stories_id allows us to run grouping queries on stories
and get accurate results.

For more information about the solr import process, see [MediaWords::Solr::Dump](lib/MediaWords/Solr/Dump.pm).

Reads from the solr database are performed through the [MediaWords::Solr](lib/MediaWords/Solr.pm) module for perl code
in the codebase and through the api (which itself uses Solr.pm) by external clients.
