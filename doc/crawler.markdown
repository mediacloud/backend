Crawler
=======

The crawler is responsible downloading all feeds and stories.  The crawler consists of the
[provider](../lib/MediaWords/Crawler/Provider.pm), the [engine](../lib/MediaWords/Crawler/Engine.pm), and a specified
number of [fetcher](../lib/MediaWords/Crawler/Fetcher.pm)/[handler](../lib/MediaWords/Crawler/Handler.pm) processes. The
engine hands queued urls to the fetchers to download.  Whenever the engine runs out of queued urls, it asks the
provider to give it more.  The handlers store the downloaded content.  If the content is a feed, they also parse the
feed to find new stories and add those to the download queue.

The crawler is started by (supervisor)[supervisor.markdown].  The number of crawlers run is configured in the
supervisord section of mediawords.yml.

All downloads, including feeds and stories, are stored and processed in the downloads table.  The downloads table has
the following fields (among many others) that help control the flow of the crawling process:

| field | values                            | purpose
| ----- | --------------------------------- | ------------------------------------------------------
| state | fetching, pending, success, error | state of the downloads in the crawling process
| type  | content, feed                     | is the download a feed (feed) or story (content)?

Follow the above links to the individual modules for detailed documentation about the provider, engine, fetcher, and
handler modules.

The crawler should be running at all times, or the system will risk losing data as urls scroll past the end of the rss
feeds the system follows.  To avoid losing data during planned or unplanned downloads, we have code that allows us to
run a [temporary crawler](temporarycrawler.markdown) on a separate machine and then import the resulting data back into
the main database.
