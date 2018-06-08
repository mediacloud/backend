Solr
====

Media Cloud uses Solr as its text indexing and search engine. For information on running the Solr engine, see the [hosting docs](hosting/solr-hosting.markdown).

We use sharding within Solr to host the data across multiple server processes on each server and across
multiple servers.  Solr requires multiple shards in the same machine to take advantage of parallel processing
capabilities (including both multiple CPU cores and multiple disks) on the same machine.  The host docs referenced
above describe how we administer our Solr cluster, including scripts we use to create, start, stop, and reload
Solr shards.

The basic interaction between Solr and the rest of the platform is that we import any updated `story_sentences` into
Solr from the PostgreSQL server every hour by running an hourly Cron script on the Solr server.  The import script
knows which sentences to import by keep track of `db_row_last_updated` fields on the `stories`, `media`, and `story_sentences`
table.  The import script queries `story_sentences` for all distinct stories for which the `db_row_last_updated` value
is greater than the latest value in `solr_imports`.  Triggers in the PostgreSQL database update the
`story_sentences.db_row_last_updated` value on `story_sentences` whenever a related story, medium, story tag,
medium tag, or story sentence tag is updated.

The list of fields imported by Solr is configured in
[solr/collections/_base_collection/conf/schema.xml](../solr/collections/_base_collection/conf/schema.xml).  As of this doc, we index the
following fields:

* `story_sentences_id` (stored; must look up the specific returned sentence)
* `media_id`
* `stories_id` (stored; must return grouped stories_id to efficiently search for lists of stories)
* `sentence_number`
* `processed_stories_id` (stored; must query PostgreSQL for returned `stories_id`s ordered by specific `processed_stories_id`)
* `sentence` (stored; must get sentence back to efficiently count words without querying `story_sentences`)
* `title` (stored; must get title back to efficiently count words)
* `publish_date`
* `publish_day`
* `language`
* `tags_id_stories`
* `tags_id_media`
* `tags_id_story_sentences`

Stored fields mean that they are going to be returned by Solr queries. Storing fields in addition to indexing them
requires significant extra resources (disk space, import time, query time), so we should not store fields unless
there is a good reason for not just querying the results from PostgreSQL once we get the `stories_id`s back.

Stories (titles) are stored as separate documents.  So, a story with ten sentences will be imported as 11 documents -- 10 documents
with the sentence field set and 1 with the title field set.

For the `solr_id`, we use `<stories_id> | <story_sentences_id>` (for example `1234|123456`), which allows Solr to store
sentences from the same story on the same shard.  Sharding by `stories_id` allows us to run grouping queries on stories
and get accurate results.

For more information about the Solr import process, see [MediaWords::Solr::Dump](lib/MediaWords/Solr/Dump.pm).

Reads from the Solr database are performed through the [MediaWords::Solr](lib/MediaWords/Solr.pm) module for Perl code
in the codebase and through the API (which itself uses Solr.pm) by external clients.
