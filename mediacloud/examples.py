
import couchdb
from pubsub import pub
import nltk
from mediacloud.readability.readabilitytests import ReadabilityTool

ENGLISH_STOPWORDS = set(nltk.corpus.stopwords.words('english'))

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
    db_story['word_count'] = getWordCount(raw_story['story_text'])

def getWordCount(text):
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
    gradeLevel = getFleshKincaidGradeLevel( raw_story['story_text'] )
    if (gradeLevel != None):
        db_story['fk_grade_level'] = gradeLevel

def getFleshKincaidGradeLevel(text):
    '''
    Get the grade reading level of a piece of text.  This relies on patched ntlk_contrib
    code, stored in the mediacloud.readability module (cause the published code don't
    work!).
    '''
    r = ReadabilityTool()
    gradeLevel = None
    if isEnglish(text):
        try:
            if (text!=None) and (len(text)>0) :
                gradeLevel = r.FleschKincaidGradeLevel(text.encode('utf-8'))
        except (KeyError, UnicodeDecodeError):
            pass
    return gradeLevel

def addIsEnglishToStory(db_story, raw_story):
    '''
    Simple hook to add a value that guesses if this article is in english or not
    '''
    matchesEnglish = isEnglish( raw_story['story_text'] )
    db_story['is_english'] = matchesEnglish

def isEnglish(text):
    '''
    A simple hack to detect if an article is in english or not.
    See http://www.algorithm.co.il/blogs/programming/python/cheap-language-detection-nltk/
    '''
    matchesEnglish = False
    if (text!=None) and (len(text)>0) :
        text = text.lower()
        words = set(nltk.wordpunct_tokenize(text))
        matchesEnglish = len(words & ENGLISH_STOPWORDS) > 0
    return matchesEnglish

def getAllExampleViews():
    return {
      "_id": "_design/examples",
      "language": "javascript",
      "views": {
            "max_story_id": {
                "map": "function(doc) { emit(doc._id,doc._id);}",
                "reduce": "function(keys, values) { var ids = [];  values.forEach(function(id) {if (!isNaN(id)) ids.push(id); }); return Math.max.apply(Math, ids); }"
            },
            "total_stories": {
                "map": "function(doc) { emit(null,1); }",
                "reduce": "function(keys, values) { return sum(values); }"
            },
            "word_counts": {
                "map": "function(doc) { emit(200*Math.floor(doc.word_count/200),1); }",
                "reduce": "function(keys, values) { return sum(values); }"
            },
            "source_word_counts": {
                "map": "function(doc) { var wc = 200*Math.floor(doc.word_count/200); var host = doc.guid.match(/:\/\/(www\.)?(.[^/:]+)/)[2]; var hostParts = host.split('.'); var domain = hostParts.slice(hostParts.length-Math.min(hostParts.length,2)).join('.'); emit(domain+'_'+wc, 1); }",
                "reduce": "function(keys, values) { return sum(values); }"
            },
            "is_english": {
                "map": "function(doc) { emit(doc.is_english,1); }",
                "reduce": "function(keys, values) { return sum(values); }"
            },
            "reading_grade_counts": {
                "map": "function(doc) { emit(Math.round(doc.fk_grade_level),1); }",
                "reduce": "function(keys, values) { return sum(values); }"
            },
            "source_reading_grade_counts": {
                "map": "function(doc) { var rgl = Math.round(doc.fk_grade_level); rgl = (rgl<10 && rgl>=0) ? '0'+rgl : rgl; var host = doc.guid.match(/:\/\/(www\.)?(.[^/:]+)/)[2]; var hostParts = host.split('.'); var domain = hostParts.slice(hostParts.length-Math.min(hostParts.length,2)).join('.'); emit(domain+'_'+rgl, 1); }",
                "reduce": "function(keys, values) { return sum(values); }"
            },
            "domain_three_part": {
                "map": "function(doc) { var host = doc.guid.match(/:\/\/(www\.)?(.[^/:]+)/)[2]; var hostParts = host.split('.'); var domain = hostParts.slice(hostParts.length-Math.min(hostParts.length,3)).join('.'); emit(domain, 1); }",
                "reduce": "function(keys, values) { return sum(values); }"
            },
            "domain_two_part": {
                "map": "function(doc) { var host = doc.guid.match(/:\/\/(www\.)?(.[^/:]+)/)[2]; var hostParts = host.split('.'); var domain = hostParts.slice(hostParts.length-Math.min(hostParts.length,2)).join('.'); emit(domain, 1); }",
                "reduce": "function(keys, values) { return sum(values); }"
            },
            "source_stories": {
                "map": "function(doc) { var host = doc.guid.match(/:\/\/(www\.)?(.[^/:]+)/)[2]; var hostParts = host.split('.'); var domain = hostParts.slice(hostParts.length-Math.min(hostParts.length,2)).join('.'); emit(domain, doc); }"
            },
           "source_story_counts": {
               "map": "function(doc) { var host = doc.guid.match(/:\/\/(www\.)?(.[^/:]+)/)[2]; var hostParts = host.split('.'); var domain = hostParts.slice(hostParts.length-Math.min(hostParts.length,2)).join('.'); emit(domain, 1); }",
               "reduce": "function(keys, values) { return sum(values); }"
           }
      }
    }
