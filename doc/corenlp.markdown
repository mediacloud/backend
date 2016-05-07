CoreNLP Annotator
=================

We run some of our stories through the Stanford CoreNLP annotation library to perform entity extraction.  The CoreNLP
results give us a list of all of the people, places, and organizations mentioned in each story.  We do not generate
any metadata directly from these results because they are pretty messy.  But we provide access to them through the
API so that other folks can write clients that consume the raw entity data from CoreNLP and generate a usable set
of tags.  This is the process we use to generate our geotags.

CoreNLP annotation is performed by a pool of job workers on the core machine.  After each story is extracted,
the post-processing includes a step that checks whether the story is part of a media for which the
'annotate_with_corenlp' field is true.  If that check is false, the story is immediately added to the processed_stories
list, indicating that core processing is done on the story.  

If the check is true, a job is added to the CoreNLP queue.  When a CoreNLP worker picks up that job, it calls a CoreNLP
annotation web service run on a separate machine to perform the annotation for each individual sentence and for the
whole story together.  That web service returns a json file, which the CoreNLP worker stores in a CoreNLP content
store (using the pluggable storage system we use to store story content, which can point to either postgres or to
amazon s3).  Once the json result has been stored, the CoreNLP worker adds the story to the processed stories list.

The purpose of the processed stories list is to stream stories to API users as they are finished with processing
(download, extraction, annotation).  So an API client that is streaming a query that includes queries that include
stories marked for CoreNLP annotation will only see the story once it has been annotated by the CoreNLP worker.

More information about the CoreNLP web service [here](hosting/corenlp-hosting.markdown).
