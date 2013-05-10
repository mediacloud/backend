
from pubsub import pub
import nltk
from mediacloud.readability.readabilitytests import ReadabilityTool
import tldextract
from mediacloud.storage import MongoStoryDatabase
import math
from bson.code import Code

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

def addDomainInfoToStory(db_story, raw_story):
    '''
    add the broken up domain info
    '''
    info = getDomainInfo(db_story)
    db_story['domain'] = {}
    db_story['domain']['subdomain'] = info.subdomain
    db_story['domain']['domain'] = info.domain
    db_story['domain']['tld'] = info.tld

def getDomainInfo(db_story):
    if db_story['guid'].find('http://') == 0:
        source = db_story['guid']
    else:
        source = db_story['url']
    return tldextract.extract(source)

class ExampleMongoStoryDatabase(MongoStoryDatabase):

    def englishStoryCount(self):
        return self._db.stories.find({"is_english":True}).count()

    def storyLengthFreq(self, bucketSize=200, domain=None):
        if domain == None:
            map = Code("function () {"
                    "   var key = "+str(bucketSize)+"*Math.floor(this.word_count/"+str(bucketSize)+");"
                    "   if(!isNaN(key)) emit(key,1);"
                    "}")
            results_name = "story_length_freq"
        else:
            domain_parts = domain.split(".")
            map = Code("function () {"
                    "   if(this.domain.domain==\""+domain_parts[0]+"\" && this.domain.tld==\""+domain_parts[1]+"\"){"
                    "       var key = "+str(bucketSize)+"*Math.floor(this.word_count/"+str(bucketSize)+");"
                    "       if(!isNaN(key)) emit(key,1);"
                    "   }"
                    "}")
            results_name = "story_length_freq_"+domain[0]+"_"+domain[1]
        reduce = Code("function (key, values) {"
                        "   var total = 0;"
                        "   for (var i = 0; i < values.length; i++) {"
                        "       total += values[i];"
                        "   }"
                        "   return total;"
                        "}")
        rawResults = self._db.stories.map_reduce(map, reduce, results_name)
        results = self._resultsToDict(rawResults)
        # fill in any blanks so we can chart this easily
        maxWords = max(results.keys(), key=int)
        bucketCount = int(math.ceil( maxWords / bucketSize ))
        for bucket in range(bucketCount):
            if not (bucket*bucketSize in results.keys()):
                results[bucket*bucketSize] = 0
        return results

    def storyReadingLevelFreq(self,domain):
        if domain == None:
            map = Code("function () {"
                    "   emit(Math.round(this.fk_grade_level),1);"
                    "}")
            results_name = "story_reading_level_freq"
        else:
            domain_parts = domain.split(".")
            map = Code("function () {"
                    "   if(this.domain.domain==\""+domain_parts[0]+"\" && this.domain.tld==\""+domain_parts[1]+"\"){"
                    "       emit(Math.round(this.fk_grade_level),1);"
                    "   }"
                    "}")
            results_name = "story_reading_level_freq_"+domain[0]+"_"+domain[1]      
        reduce = Code("function (key, values) {"
                        "   var total = 0;"
                        "   for (var i = 0; i < values.length; i++) {"
                        "       total += values[i];"
                        "   }"
                        "   return total;"
                        "}")
        rawResults = self._db.stories.map_reduce(map, reduce, "story_reading_level_freq")
        results = self._resultsToDict(rawResults)
        # fill in any blanks so we can chart this easily
        maxLevel = int(max(results.keys(), key=int))
        for level in range(maxLevel):
            if not (level in results.keys()):
                results[level] = 0
        return results

    def storyCountForSource(self, domain):
        parts = domain.split('.')
        return self._db.stories.find({'domain.domain':parts[0],'domain.tld':parts[1]}).count()

    def storyCountBySource(self):
        map = Code("function () {"
                    "   emit(this.domain.domain+'.'+this.domain.tld, 1);"
                    "}")
        reduce  = Code("function (key, values) {"
                        "   var total = 0;"
                        "   for (var i = 0; i < values.length; i++) {"
                        "       total += values[i];"
                        "   }"
                        "   return total;"
                        "}")
        rawResults = self._db.stories.map_reduce(map, reduce, "story_count_by_source")
        return self._resultsToDict(rawResults)

    def _resultsToDict(self, rawResults):
        ''' 
        Helper to change a key-value set of results into a python dict
        '''
        results = {}
        for doc in rawResults.find():
            results[ doc['_id'] ] = doc['value']
        return results    
