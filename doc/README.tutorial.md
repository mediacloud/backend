# Tutorial

Following is a brief tutorial walking through the process of adding a media
source to the database and downloading, extracting, and tagging the stories
from the source.

* Go to the admin home page of the web app which at `admin/media/list`
    * eg. (<http://localhost:3000/admin/media/list> if running `mediawords_server.pl` on your local machine).
  
* Click on *Add Media*.

* Enter `http://nytimes.com/` in the text box and click on the
  *Add media* button.
  
* Verify that you got a *Successfully Added/Updated: http://nytimes.com*
  message.
  
* Click on *Home*.

* Click on the *Feeds* link for nytimes.com.

* You are now on the feed scraping page for nytimes.com.  Enter 
  `http://www.nytimes.com/services/xml/rss/index.html` in the URL field
  and click on the *Scrape* button.
  
* After a couple of minutes, you should see a list of about 25 nytimes
  feeds.  Scroll to the bottom of the list and click on the *Import Feeds*
  button.
  
* You now have a media source with a collection of feeds to download.

* Run `script/mediawords_crawl.pl` and watch for a few minutes as the crawler
  fetches first the feeds and then the stories within the feeds.

* Run `script/mediawords_extract_and_vector_locally.pl` in a separate window.
  Once the crawler has downloaded some stories, you should see the extractor
  finding downloads and extracting and tagging them.
    * e.g. `nohup mediawords_crawl.pl &> /var/log/mediacloud_crawl.lo &`
    * `mediawords_crawl.pl` and `mediawords_extract_and_vector_locally.pl` are both
  designed as daemons that should run in the background writing to a log file
  in a production system.  They will automagically find new content as it is
  created.

* Return to the home page of the web app.  Click on the the *Feeds* link
  for nytimes.com.
  
* Click on one of the feeds downloaded during the crawling (*NYT > Home Page*
  is likely to work).
  
* You should see a list of stories found in that feed, but the latest
  stories are likely not to have been downloaded / extracted / tagged yet, so
  click on the *next page* link at the bottom of the feed page (if there is
  one) until you get to the last page, then click on the last story.
  
* If that story has been downloaded and extracted, you should see the tags
  for the story in *Tags:* field of that page, as well as the extracted
  text.  If it has not been extracted there will be no tags and a
  *(downloads pending extraction)* note at the bottom of the extracted
  text field (the info about that note is just the title and description
  of the story).

* That's the gist of the system.  As you add new media sources and feeds
  the crawler and extractor scripts running in the background will find 
  them and start downloading them as well.
