Crawler
=======

The crawler is responsible downloading all feeds and stories.  The crawler consists of the
[provider](../lib/MediaWords/Crawler/Provider.pm), the [engine](../lib/MediaWords/Crawler/Engine.pm), and a specified
number of [fetcher](../lib/MediaWords/Crawler/Fetcher.pm)/[handler](../lib/MediaWords/Crawler/Handler.pm) processes.
The engine hands urls to the fetchers to download.  The handlers  store the downloaded content.  If the content is a
feed, parse the feed to find new stories and add those to the download queue.

All downloads, including feeds and stories, are stored and processed in the downloads table.  The downloads table has
the following fields (among many others) that help control the flow of the crawling process:

| field | values                            | purpose
| ----- | --------------------------------- | ------------------------------------------------------
| state | fetching, pending, success, error | state of the downloads in the crawling process
| type  | content, feed                     | is the download a feed (feed) or story (content)?

Engine
------

The crawler engine coordinates the work of the provider and the fetcher/handler processes.  It first forks the specified
number of fetcher/handler processes and opens a socket connection to each of those processes. It then listens for
requests from each of those processes.  Each fetcher/handler process works in a loop of requesting  a url from the
engine process, dealing with that url, and then fetching another url from the engine.  

The engine keeps in memory a queue of urls to download, handing out each queued url to a fetcher/handler
process when requested.  When the in memory queue of urls runs out, the engine calls the provider library to generate
a list of downloads to keep in the memory queue.

Provider
--------

The provider] is responsible for provisioning downloads for the engine's in memory downloads queue.  The basic job
of the provider is just to query the downloads table for any downloads with `state = 'pending'`.  As detailed in the
handler section below, most `'pending'` downloads are added by the handler when the url for a new story is discovered
in a just download feed.  

But the provider is also responsible for periodically adding feed downloads to the queue.  The provider uses a backoff
algorithm that starts by downloading a feed five minutes after a new story was last found and then doubles the delay
each time the feed is download and no new story is found, until the feed is downloaded only once a week.

The provider is also responsible for throttling downloads by site, so only a limited number of downloads for each site
are provided to the the engine each time the engine asks for a chunk of new downloads.

Fetcher
-------

The fetcher is the simplest part of the crawler.  It merely uses LWP to download a url and passes the resulting
HTTP::Response to the Handler.  The fetcher has logic to follow meta refresh redirects and to allow http authentication
according to settings in mediawords.yml.  The fetcher does not retry failed urls (failed downloads may be requeued by
the handler).  The fetcher passes the download response to the handler by calling
MediaWords::Crawler::Handle::handle_response().

Handler
_______

The handler is responsible for accepting the http response from the fetcher, performing whatever logic is required
by the system for the given download type, and storing successful response content in content store.

For all downloads, the handle stores the content of successful downloads in the content store system (either a local
posgres table or, on the production media cloud system, in amazon s3).

If the download has a type of 'feed', the handler parses the feed and looks for the urls of any new stories.  A story
is considered new if the url or guid is not already in the database for the given media source and if the story
title is unique for the media source for the calendar week.  If the story is new, a story is added to the stories
table and a download with a type of 'pending' is added to the downloads table.

For 'feed' downloads, after parsing the feed but before checking for new stories, we generate a checksum of the sorted
urls of the feed.  We check that checksum against the last_checksum value of the feed, and if the value is the same, we
store '(redundant feed)' as the content of the feed and do not check for new stories.  This check prevents frequent
storage of redundant feed content and also avoids the considerable processing time required to check individual
urls for new stories.

If the download has a type of 'content', the handler merely stores the content for the given story and then queues
an extraction job for the download.

If the response is an error and the status is a '503' or a '500 read timeout', the handler queues the download for
another attempt (up to a max of 5 retries) with a backoff timing starting at one hour.  If the response is an error
with another status, the 'state' of the download is set to 'error'.
