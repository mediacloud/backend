# Bit.ly processing

In order to measure the social impact that each story might have had, we use [Bit.ly's API](http://dev.bitly.com/) to get the total click count of each story by reverse-matching the story's URL with Bit.ly shortened link(s) and then adding up the click counts of each of those shortened links together.

After collecting and extracting the story, we postpone the collection of the click count for 3 and 30 days, i.e. we collect the total click counts for the story twice - after 3 and after 30 days since its publication (or collection) date.

Fetching the click count 3 days after story publication allows us to get some link impact data sooner than later, and at 30 days we refetch the count to get the "full" click count as we found out that most of the Bit.ly link clicks happen within 30 days since story gets published.


## Steps

1. After extracting a newly collected story, `::DBI::Stories::process_extracted_story()` calls `::Util::Bitly::Schedule::add_to_processing_schedule()` which adds the story to Bit.ly's processing schedule.

2. `add_to_processing_schedule()` adds two rows for each story to `bitly_processing_schedule` table in order to (re)fetch the total story's click count after 3 and 30 days since its publication or collection date.

3. `mediawords_process_bitly_schedule.pl` is being run periodically and adds due stories from `bitly_processing_schedule` table to `::Job::Bitly::FetchStoryStats` job queue for the click count to be (re)fetched.

4. `::Job::Bitly::FetchStoryStats` worker fetches a list of days and clicks from Bit.ly API, stores the raw JSON response on Amazon S3, and adds `::Job::Bitly::AggregateStoryStats` job which will in turn process the raw data just fetched (add daily click counts into a single total click count).

5. `::Job::Bitly::AggregateStoryStats` fetches the raw JSON response from S3 (or from the local cache), adds daily click counts together to get the total story's click count, stores the total count in `bitly_clicks_total` table, and lastly adds the story to the Solr processing queue so that the story gets reimported into Solr with the total click count now being present.


## Notes

* By default, Bit.ly statistics collection is postponed 3 and 30 days from story's publication date (`stories.publish_date`). However, if said date doesn't look valid (is before year 2008 when Media Cloud project started, or in the future), Bit.ly scheduler falls back to story's collection date (`stories.collect_date`) as it is assumed that the crawler collects the story pretty quickly after it appears online so the collection date is pretty close to story's actual publication date.
