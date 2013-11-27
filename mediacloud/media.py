
import os
import unicodecsv as csv

media_sources = None
media_sets = None

def source(media_id):
    '''
    Call this to get info about a particular media source that you know the id of
    '''
    global media_sources
    if media_sources == None: 
        media_sources = {}
        MEDIA_FILE_PATH = os.path.dirname(__file__)+'/data/media_ids.csv'
        media_file = open(MEDIA_FILE_PATH, 'rb')
        csv_reader = csv.reader(media_file, encoding='utf-8')
        header = csv_reader.next() # skip header
        for row in csv_reader:
            m_id = int(row[0])
            media_sources[m_id] = {}
            for idx, column_name in enumerate(header):
                media_sources[m_id][column_name] = row[idx]
    return media_sources[int(media_id)]

def set(media_set_id):
    '''
    Call this to get info about a particular media set that you want to know about
    '''
    global media_sets
    if media_sets == None: 
        media_sets = {}
        MEDIA_FILE_PATH = os.path.dirname(__file__)+'/data/media_sets.csv'
        media_file = open(MEDIA_FILE_PATH, 'rb')
        csv_reader = csv.reader(media_file, encoding='utf-8')
        header = csv_reader.next() # skip header
        for row in csv_reader:
            m_id = int(row[0])
            if m_id not in media_sets:
                media_sets[m_id] = { 'id': m_id, 'name': row[1], 'media_ids': [] }
            media_sets[m_id]['media_ids'].append(int(row[2]))
    return media_sets[int(media_set_id)]
