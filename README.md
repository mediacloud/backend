MediaCloud Python API Client
============================

This is the source code of the python client for the [MediaCloud API v2](https://github.com/berkmancenter/mediacloud/blob/master/doc/api_2_0_spec/api_2_0_spec.md).

*You need an API key to use this, so be sure to ask us for one first!*

Installation
------------

Download the distribution zip, then run

    python setup.py install

Install and run [CouchDB](http://couchdb.apache.org) or [MongoDb](http://mongodb.org) to store 
article info.

*Dependencies*

```
pip install pypubsub corenlp resource
```

Examples
--------

Get a list of all the sentences from the US mainstream media that mentioned "Zimbabwe" and "president" in 2013:
```python
import mediacloud
mc = mediacloud.api.MediaCloud('MY_API_KEY')
res = mc.sentenceList('( zimbabwe AND president)', '+publish_date:[2013-01-01T00:00:00Z TO 2013-12-31T00:00:00Z] AND +media_sets_id:1')
print res['response']['numFound'] # prints the number of sentences found
```

Find the most commonly used words in sentences from the US mainstream media that mentioned "Zimbabwe" and "president" in 2013:
```python
import mediacloud
mc = mediacloud.api.MediaCloud('MY_API_KEY')
words = mc.wordCount('( zimbabwe AND president)', '+publish_date:[2013-01-01T00:00:00Z TO 2013-12-31T00:00:00Z] AND +media_sets_id:1')
print words[0]  #prints the most common word
```

To find out all the details about one particular story by id:
```python
import mediacloud
mc = mediacloud.api.MediaCloud('MY_API_KEY')
story = mc.story(169440976)
print story['url']  # prints the url the story came from
```

To get all the stories associated with a query and dump the output to json:
```import mediacloud
import json
mc = mediacloud.api.MediaCloud('')
res = mc.sentenceList('( hacking AND civic ) OR ( hackathon AND civic)', '+publish_date:[2013-01-01T00:00:00Z TO 2014-04-19T00:00:00Z] AND +media_sets_id:1')
story_ids = []
[story_ids.append(i) for i in [y["stories_id"] for y in res["response"]["docs"]] if not story_ids.count(i)]
stories = [mc.story(i) for i in story_ids]
print json.dumps(stories)
```


Take a look at the `apitest.py` for more detailed examples.

Testing
-------

First run all the tests.  Copy `mc-client.config.template` to `mc-client.config` and edit it.
Then run `python tests.py`.

Notice you get a `mediacloud-api.log` that tells you about each query it runs.

Distribution
------------

To build the distributon, update the version numbers in `mediacloud/__init__.py` and `setup.py`.
Then run `python setup.py sdist` and a compressed file will be created in the `dist` directory.
