MediaCloud Python API Client
============================

This is the source code of the python client for the [MediaCloud API v2](https://github.com/berkmancenter/mediacloud/blob/master/doc/api_2_0_spec/api_2_0_spec.md).

*You need an API key to use this, so be sure to ask us for one first!*

Installation
------------

Clone this git repo

Install the distribution egg from the ```dist``` directory by running:

```
sudo easy_install dist/mediacloud-<VERSION>.egg
```
where `**<VERSION>**` is the egg version. E.g.

```
sudo easy_install dist/mediacloud-2.22.0-py2.7.egg
```

*Dependencies*

```
pip install -r requirements.pip
easy_install pypubsub
```

Examples
--------

To get all the stories associated with a query and dump the output to json:
```python
import mediacloud, json
mc = mediacloud.api.MediaCloud('MY_API_KEY')
stories = mc.storyList('( hacking AND civic ) OR ( hackathon AND civic)', '+publish_date:[2013-01-01T00:00:00Z TO 2014-04-19T00:00:00Z] AND +media_sets_id:1')
print json.dumps(stories)
```

Find out how many sentences in the US mainstream media that mentioned "Zimbabwe" and "president" in 2013:
```python
import mediacloud
mc = mediacloud.api.MediaCloud('MY_API_KEY')
res = mc.sentenceCount('( zimbabwe AND president)', '+publish_date:[2013-01-01T00:00:00Z TO 2013-12-31T00:00:00Z] AND +media_sets_id:1')
print res['count'] # prints the number of sentences found
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

To save the first 100 stories from one day to a database:
```python
import mediacloud
mc = mediacloud.api.MediaCloud('MY_API_KEY')
db = mediacloud.storage.MongoStoryDatabase('one_day')
stories = mc.storyList('*', '+publish_date:[2014-01-01T00:00:00Z TO 2014-01-01T23:59:59Z]',0,100)
[db.addStory(s) for story in stories]
print db.storyCount()
```

Take a look at the `apitest.py` and `storagetest.py` for more detailed examples.

Testing
-------

First run all the tests.  Copy `mc-client.config.template` to `mc-client.config` and edit it.
Then run `python tests.py`.

Notice you get a `mediacloud-api.log` that tells you about each query it runs.

Distribution
------------

To build the distributon, update the version numbers in `mediacloud/__init__.py` and `setup.py`.
Then run `python setup.py bdist_egg` and a new egg will be laid in the `dist` directory.
