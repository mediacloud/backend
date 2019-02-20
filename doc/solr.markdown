Solr
====

Media Cloud uses Solr as its text indexing and search engine. For information on running the Solr engine, see the [hosting docs](hosting/solr-hosting.markdown).

We use sharding within Solr to host the data across multiple server processes on each server and across
multiple servers.  Solr requires multiple shards in the same machine to take advantage of parallel processing
capabilities (including both multiple CPU cores and multiple disks) on the same machine.  The host docs referenced
above describe how we administer our Solr cluster, including scripts we use to create, start, stop, and reload
Solr shards.

The basic interaction between Solr and the rest of the platform is that we import any updated `story_sentences` into
Solr from the PostgreSQL server every minute via the `imoport_solr_data` supervisord daemon.  That script finds which
stories to import by using the `solr_import_stories` postgres table.  Rows are added to that table by triggers
associated with the `stories` and `stories_tags_map` tables.

The list of fields imported by Solr is configured in
[solr/collections/_base_collection/conf/schema.xml](../solr/collections/_base_collection/conf/schema.xml).  As of this doc, we index the
following fields:

* `media_id`
* `stories_id`
* `processed_stories_id`
* `text`
* `title`
* `publish_date`
* `publish_day`
* `publish_week`
* `publish_month`
* `publish_year`
* `language`
* `tags_id_stories`
* `timespans_id`

Additionally, there is code in Solr.pm that converts any `tags_id_media` or `collections_id` clauses into `media_id`
clauses.  We do this conversion in code because it prevents us from having to reimport millions of stories when we
redefine collections.

Other than the text and title fields, all of the above fields are stored in solr as docvalues, because docvalues 
allow much faster grouping and also gives us stored values without requiring extra storage space.  The `text` and
`title` fields are not stored because storing the values takes about twice as much space (which also impacts
performance because it requires more memory use).

For more information about the Solr import process, see `import-solr-data`.

Reads from the Solr database are performed through the [MediaWords::Solr](lib/MediaWords/Solr.pm) module for Perl code
in the codebase and through the API (which itself uses Solr.pm) by external clients.
