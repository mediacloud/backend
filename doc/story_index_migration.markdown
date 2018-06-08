# Story Indexing Migration

This is a user directed document describing the nature and implications of our migration to story based indexing.

TLDR:

We currently do most analysis and searching at the sentence level. We're switching to do everything at the story level on May 12, because that is what most people tell use they want. This will also help us save space and make things faster. This is a big change.  Your current queries and topics will need to be updated after May 12 and will produce different results.

Details:

On May 12, Media Cloud will switch from its current sentence based indexing to story based indexing.  This a big change with major implications for both how users query our database and the results they get back.  The following document will describe how we currently index and search text, how we will change that behavior on May 12, and specific changes in our data and tools that can be expected by users.

Currently, Media Cloud parses each story into individual sentences and stores those sentences as individual documents in our solr index.  This approach has the advantage of giving highly relevant results for boolean queries but has the major disadvantages of being confusing for users expecting story based indexing, of not supporting story negation (stories that mention health but not insurance), and of making our back end index much more resource intensive to run.

On May 12, we will switch over to a story based index.  This means that the query [health and wellness] will return all stories including the words 'health' and 'wellness' anywhere in the *story* instead of the current behavior of returning all stories with at least one *sentence* that includes both 'health' and 'wellness'.  This change means that most queries that include an 'and' term anywhere in the query will return different results.  Queries that match only a single text field, eg. [health], and queries that match any of a list of words, eg. [health or wellness] or [health wellness], will return exactly the same results.

For many use cases, it will still be useful to execute queries with more precision than an entire story.  We already support proximity searches for these cases.  So you will be able to query ["health wellness"~10] to find all stories that include 'health' and 'wellness' within 10 words of each other.  The default quoted search does not support wildcards, but we will offer a special syntax to allow searching for ["health well*"~10].

At the moment of the switchover, we will add a legacy flag to all existing topics and saved explorer searches.  The topics will refuse to spider and the explorer searches will refuse to return results until the user has confirmed that the query has been modified or just confirmed to work with the new story based index.  Existing topic snapshots will not be impacted in any way, so you can trust existing topic results not to change.  You just will not be able to respider an existing topic without manually confirming the query you want to use.

Existing results of explorer searches created using the sentence based index will no longer be available as of May 12.  If you need existing explorer searches to remain the same for an ongoing or published project, you need to archive the search results before May 12.  It is best practice in any case to archive any explorer searches on which you rely because our data changes over time and explorer searches are always rerun when you view them.

In order to approximate the existing word cloud results, we will be using a hybrid approach to generating word clouds with the story based index.  For the existing sentence based index word clouds, we just count the words in a sample of sentences that match the query.  For the new story based index word cloud, we will first fetch a sample of stories that match the query and then count the words for any sentences within those stories that match any of the terms in the query.  So a word cloud for the query [health and wellness] or ["health wellness"~10] will count the words in all sentences including either of the words 'health' or 'wellness' in a sample of stories that mention both terms.

Because we rely on the solr index to efficiently count results over time, we are moving the time sliced results functionality from the sentences/count api end point to the stories/count end point.  This means that you will not longer be able to quickly count sentences over time.  The front end tools will all be updated to show stories over time histograms rather than sentences over time.
