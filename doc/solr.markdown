Solr
====

Media Cloud uses solr as its text indexing and search engine.

The Media Cloud repo has a solr 4.6 distribution included within it in the solr/ directory.  For information on running
the solr engine, see the [hosting docs](hosting/solr-hosting.markdown).

The basic interaction between solr and the rest of the platform is that we import any updated story_sentences into
solr from the postgres server every hour by running an hourly cron script on the solr server.  The import script
knows which sentences to import by keep track of db_row_last_updated fields on the stories, media, and story_sentences
table.  The import script queries story_sentences for all distinct stories for which the db_row_last_updated value
is greater than the latest value in solr_imports.  Triggers in the postgres database update the
story_sentences.db_row_last_updated value on story_sentences whenever a related story, medium, story tag,
medium tag, or story sentence tag is updated.

For more information about the solr import process, see [MediaWords::Solr::Dump](lib/MediaWords/Solr/Dump.pm).

Reads from the solr database are performed through the [MediaWords::Solr](lib/MediaWords/Solr.pm) module for perl code
in the codebase and  through the api by external clients.
