
import couchdb
from pubsub import pub
import nltk

'''
This file holds some simple example functions that process a story and add some piece
of metadata to it, for saving into the database.  You can base your (hopefully more 
useful) plugin on these examples.
'''

def addWordCountToStory(db_story, raw_story):
    '''
    Simple hook to add the extracted text word count to the database.
    Use this in a pre-save callback to get the new "word_count" column.
    '''
    text = nltk.Text(raw_story['story_text'].encode('utf-8'))
    word_count = len(text)
    db_story['word_count'] = word_count
