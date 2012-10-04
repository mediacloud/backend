
import couchdb
from pubsub import pub
import nltk
from mediacloud.readability.readabilitytests import ReadabilityTool

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
    db_story['word_count'] = _getWordCount(raw_story['story_text'])

def _getWordCount(text):
    '''
    Count the number of words in a body of text
    '''
    text_list = nltk.Text(text.encode('utf-8'))
    word_count = len(text_list)
    return word_count
        
def addFleshKincaidGradeLevelToStory(db_story, raw_story):
    '''
    Simple hook to add the Flesch-Kincaid Grade to the database.  This uses a pre-save
    callback to add a new 'fk_grade_level' column. 
    '''
    gradeLevel = _getFleshKincaidGradeLevel( raw_story['story_text'] )
    if (gradeLevel != None):
        db_story['fk_grade_level'] = gradeLevel

def _getFleshKincaidGradeLevel(text):
    '''
    Get the grade reading level of a piece of text.  This relies on patched ntlk_contrib
    code, stored in the mediacloud.readability module (cause the published code don't
    work!).
    '''
    r = ReadabilityTool()
    gradeLevel = None
    try:
        if (text!=None) and (len(text)>0) :
            gradeLevel = r.FleschKincaidGradeLevel(text.encode('utf-8'))
    except (KeyError, UnicodeDecodeError):
        pass
    return gradeLevel
