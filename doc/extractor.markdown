Extractor
=========

The extractors are responsible for parsing the substantive text from the raw html of each story and storing it in the
download_texts table.  The extractor also parses the download_text into sentences and stores those sentences in the
story_sentences table.  An extractor job is queued by the crawler handler for each story it downloads.

A strong principle of media cloud is to use only generic algorithms for data processing, rather than site specific
scraping.  For text extraction, we use [python-readability](https://github.com/timbertson/python-readability).  We
performed an extensive evaluation of various freely available extraction libraries, along with our own home brew
extractor we had been using for years, and found that python-readability performed best for our data across all
different media sets, languages, and crawled vs. spidered stories.  Our python-readability based extractor has an F1
of about 0.91 across all of these test cases.

The extractor jobs run as job workers, which are started by supervisor.  The number of extractor jobs run at once
is configured in the supervisord section of mediawords.yml.

The algorithmic work of extracting substantive content from a web page is done by the perl extractor worker calling a
python Thrift  web service (also started by supervisor and configured in mediawords.yml).

The extractor worker actually does a variety of processing tasks related to extraction.  Most of the below is done by
by MediaWords::StoryVectors::update_story_sentences_and_language, which is called immediately after extraction.
Altogether, the extractor:

* pulls the content for the stories downloads from the content store;
* substitutes the title and description (from the rss feed) for the content if no content was found;
* calls the thrift web service to do the extraction work;
* strips html from the extracted content returned by the thrift web service;
* stores the resulting extracted text in download_texts;
* detects the language of the story using the [chromium compact language
  detection library](https://github.com/mikemccand/chromium-compact-language-detector);
* parses the extracted text into individual sentences;
* removes duplicates sentences for the same media source for the same calendar week;
* detects the language of each sentence;
* stores each sentence in story_sentences;
* runs an ap syndication detection algorithm on the story;
* queues a corenlp annotation for the story if the story is an media source that is marked for annotation;

Relevant Code
-------------

The code that does all of the above is unfortunately spread out in many places throughout the code base.

Here are some of the places to look for specific bits of code:

* MediaWords::DBI::Downloads::extract - does some preprocessing on the content and then calls
the extraction method specified in mediawords.yml -> mediawords.extractor_method (always the python readability
extractor in production).
* MediaWords::Util::ThriftExtractor::get_extracted_html - calls the thrift python readability extractor web service
to return extracted html from the raw html
* python_scripts/extractor_python_readability_server.py - implementation of thrift python readability web service
* MediaWords::StoryVectors::update_story_sentences_and_language - does all of the above stuff after the extraction
proper (parses sentences, assigns languages, queues further work, etc)
