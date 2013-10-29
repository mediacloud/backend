Controversies
=============

This document provides a high level overview of how the controversy mapping 
system works and points to the pieces of code that performance specific
functions.

The controversy mapping system is used to generate and analyze spidered sets
of stories on some time and text pattern defined topic. The key differences
between the controversy mapping system and the rest of the system are that:

* the cm uses links in the text of existing content to spider for new content
  (in general all stories in media cloud are discovered via an rss feed) and
* as the cm parses links to discover new stories, it stores those links in the
  database so that we can use them for link analysis.


Basic flow of generating and analyzing a controversy
----------------------------------------------------

1. identify a text pattern and date range that defines the controversy (e.g.
   trayvon during 2012-03-01 - 2012-05-01);
    * the search parameters are stored in `queries_story_searches`

2. search the existing media cloud for stories that match the text and date
   range;
    * running `mediawords_search_stories.pl` runs the defined search and puts
      the results into `queries_story_searches_stories_map`
    
3. add additional seed set urls from other sources (e.g. manual research by
   RAs, twitter links, google search results);
    * these seed set urls are generated manually for now and imported into
      `controversy_seed_urls` using
      `mediawords_import_controversy_seed_urls.pl`
    
4. download all additional seed set urls that do not already exist in
   the database and add a story for each;

5. add all of the seed set stories from (2) and (3) to the controversy;

6. parse all links from the extracted html from each story in the controversy;

7. for each link, either match it to a the url of an existing story in the
   database or download it and add it as a new story;

8. for each story at the end point of a link from a controversy story, add it
   to the controversy if it matches the text pattern from (1).

9. repeat (6) - (9) for all stories newly added to the controversy, until now
   new stories are found or a maximum number of iterations is reached;
    * steps (4) - (9) are the mining process, implemented by
      `MediaWords::CM::Mine::mine_controversy`

10. dedup the media newly created during the spidering process (as each new
    story is added, a media source has to found or created for it based on the
    url host name, and often those media sources end up being duplicates, e.g.
    `articles.orlandosun.com` and `www.orlandosun.com`);
    * media deduping is implemented in `mediawords_dedup_controversy_media.pl`
    
11. manually review the controversy using the web ui, looking especially for
    odd results that might be technical artifacts and for media sources for
    deduping that were not discovered by the system in (10);
    * manual review of stories is done through the web interface, implemented
      in `MediaWords::Controller::Admin::CM`
    
12. run a dump of the controversy to create a static snapshot of the data that
    can act as a stable data set for research, to generate the time slice
    network maps, and to generate reliability scores for the influential media
    list in each time slices.
    * dumping is implemented by `MediaWords::CM::Dump::dump_controversy`
    
13. review the dump data, performing any more manual edits (editing story and
    media names, checking dates, analyzing influential media lists for each
    time slice, and so on).

14. rerun steps (4) - (9) any time new stories are added to the controversy
    (for instance after adding more seed urls) or after media sources are
    deduped.
    
15. rerun the dump (12) any time the controversy data has been changed and
    researchers need a new set of consistent results, new maps, or new
    reliability scores.
