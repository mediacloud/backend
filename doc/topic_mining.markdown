# Topic Mining

The Topic Mapper system uses link mining to provide richer data for a specific topic.  The topic is defined by a boolean query.  The topic mapper uses that boolean query to spider out from an initial set of seed stories found within the Media Cloud archive to discover more relevant stories on the open web and to add link network and social media metrics to set of stories matching that query.

Below is detailed documentation our architecture for topic spider.

## Topic Spidering Pipeline

The topic spider uses a distributed architecture including the following jobs:

* `topic_run`
* `topic_mine_story`
* `topic_fetch_link`
* `topic_add_story`
* `facebook_fetch_story_stats`
* `topic_snapshot`

Here are a simple text flow chart in mermaid and the resulting rendered chart:

[Topic Mining Chart Text](topic_mining.mermaid)

[Topic Mining Chart](topic_mining.png)

### topic_run

`topic_run` starts the process of running each topic and is responsible for running the single thread processes that need to happen before and after the distributed spidering process.

Before the distributed spidering starts, this job imports seed urls / stories into the topic, mostly by running the solr seed query and inserting the resulting stories into the topic_seed_urls postgres table.  The bulk of this work is just running the solr query and then running a bunch of inserts into the postgres table.

Each row in topic_seed_urls might contain a stories_id imported from solr or it might contain a url imported manually from a spreadsheet or from twitter scraping for a twitter topic.  The topic_seed_urls table acts as a helpful generic platform to start the spidering regardless of how the seed content comes into the system.

After inserting each story into the topic_seed_urls table, the process will create a new job each individual url / story from the topic_seed_urls table according to this routing logic:

```
if seed_has_stories_id(seed):
    topic_add_story(stories_id)
elif seed_url_matches_existing_story(seed):
    topic_add_story(stories_id)
else:
    topic_fetch_link(url)
````

After inserting all of these seed jobs into the pipeline, `topic_run` sits around waiting for the pipeline to exhaust the recursive process described below.  To determine whether the pipeline has completed its work, `topic_run` polls the topic_stories.spidered and topic_links.fetched fields periodically.  To mitigate the risk that the states on some jobs get lost, we fail the topic if it has been stuck in the polling state without the size of its pipeline decreasing for too long.

After `topic_run` has determined that the distributed spidering is done, it does some post processing.  Most importantly, it runs story deduping and media deduping on all of the stories added to the topic.  Media deduping looks for any media for which dup_media_id points to another media source and merges those stories into the parent media source. The story insertion logic in `topic_add_story` uses that same logic to avoid adding stories to duplicate media, but the set of duplicate media can change between (or during) spidering runs, so we have to run the deduping with each spidering run to keep the topic update to date with the current media duplicates data.

The story deduping process looks for duplicate stories within each media source according to story dates and title part counts.  This process uses a big list of title parts to be able to figure out that 'Washington Post: Nunes Releases FISA Memo' is the same story as 'Nunes Releases FISA Memo'.  That list of title parts would be difficult and expensive to story in postgres, so we just do it in memory for each media source, but that means that we have to do the story deduping after we already have all of the stories present in the topic, so we have to do it in as a single thread.

After the dedping is completed, `topic_run` again waits, this time for the `facebook_fetch_story_stats` pool to empty out by watching for story_statistics rows to be created for every topic in the story.  The `facebook_story_stats` jobs are added during the spidering process, so ideally there is little or no waiting at this step.

Finally, the topic starts a `topic_snapshot` job.  The topic snapshotting process is basically a bunch of (expensive for large topics) analytical queries that build up from the topic_stories and topic_links tables. The `topic_snapshot` job is currently single threaded, but we could break it up into an individual job for each timespan for future work.

### topic_mine_story

`topic_mine_story` parses links out of the link of a story that has already been added to the topic.  

Links are parsed out of only the substantive content of the story and include both html tags, urls in clear text, and some special case links for specific sites.  Each link parsed out of the story will be matched against the urls of stories already in the Media Cloud database, and the job will create either a `topic_add_story` or `topic_fetch_link` job depending on the result of that match:

```
if not link_matches_existing_story(url):
    topic_fetch_link(url)
else:
    if story_in_topic:
        end_pipeline();
    else:
        topic_add_story(story)
```

### topic_fetch_link

`topic_fetch_link` fetches a url, obeying per media source throttling, and forwards the content on to topic_add_story if it passes an initial topic relevance test.

To impose the media source throttling, `topic_fetch_link` obeys a `seconds_per_media_fetch` minimum for how many seconds must pass between fetches to the given media source and keeps track of the last time a fetch was made to a given media source in the media_fetches postgres table.  If the time since the last fetch was less than `seconds_per_media_fetch`, `topic_fetch_link` just reinserts the current job back into the end of the job queue.  Each pool worker has a limit to how many reinserts it can perform in row, after which it will start sleeping between each reinsert to avoid bombing the hosting server.

After fetching the content for a given url, `topic_fetch_url` tries to match the entire raw html (or whatever content type) against the topic relevancy pattern.  This is just a potential relevance check, whose intent is to eliminate the large of majority of downloads that cannot even potentially match the full relevancy check done in `topic_add_story`.

If the potential content match succeeded, `topic_fetch_url` generates a Media Cloud story for the content.  This story generation process includes guessing a media source based on the url, guessing a publication date based on the url and content, and guessing a title based on the html.  The resulting story is not yet added to the topic -- it is only added as a generic story within the Media Cloud database.  `topic_add_story` does the relevancy check and potentially adds the story to the topic.

Based on the results of the relevancy check, the job is routed forward with the following logic:

```
if content_matches(url):
    topic_add_story(story)
else:
    end_pipeline()
```

### topic_add_story

`topic_add_story` tests whether the story is relevant to the topic and, if so, adds it to the topic and then adds the story to `topic_mine_links` to continue the recursive spidering process.

To test relevancy, `topic_add_story` matches the substantive content of the story against the topic pattern, which is a regular expression serviced from the topic solr_seed_query.  To be relevant to the topic, either the title, description, url, or concatenated sentences of the story must match the topic pattern.  Only the non-duplicate sentences within the stories (sentences that are not duplicates within the same media source in the same calendar week) are matched against the pattern.

The topic spidering process is limited to topics.max_iterations (default: 15) iterations.  Each time a new story is added to a topic, it is given an iteration of one greater than the parent story from whose links the the new story was discovered.  The spider completes its spidering by either failing to find any new stories for a given iteration or by refusing to further process stories with an iteration greater than topics.max_iterations.

The story is routed forward in the pipeline according to this logic:
```
if story_is_relevant(story):
    facebook_fetch_story_stats(story)
    if story.iteration < topic.max_iterations:
        topic_mine_story(story)
    else:
        end_pipeline()
else:
    end_pipeline()
```

### facebook_fetch_story_stats

`facebook_fetch_story_stats` fetches share counts from the facebook api for the story and stores then in the story_statistics table.

This job never routes the story forward in the pipeline -- it runs as an offshoot process in parallel with `topic_mine_story` for stories newly added to the topic.
