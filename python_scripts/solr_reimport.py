#!/usr/bin/python

import requests
import ipdb
import mc_config
import psycopg2
import psycopg2.extras
import time

#assert pkg_resources.get_distribution("requests").version >= '1.2.3'

def get_db_info():
    config_file = mc_config.read_config()
    return config_file['database'][0]

def connect_to_database():
    db_info = get_db_info()
    conn = psycopg2.connect( database=db_info['db'], user=db_info['user'], password=db_info['pass'], host=db_info['host'], port=db_info['port'] )
    return conn
    

conn = connect_to_database()

cursor = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

pg_last_import_id_var = 'LAST_REIMPORTED_STORY_SENTENCES_ID';

cursor.execute("SELECT * from database_variables where name = %s ", (pg_last_import_id_var,) )
#ipdb.set_trace()

result = cursor.fetchone()
if result == None:
    cursor.execute( "SELECT min(story_sentences_id)  from story_sentences")
    min_story_sentences_id = cursor.fetchone()['min']
    print min_story_sentences_id 
    cursor.execute("INSERT INTO database_variables(name, value) VALUES( %(name)s, %(value)s )", 
                   { 'name': pg_last_import_id_var, 'value': min_story_sentences_id - 1 } )
    conn.commit()
else:
    min_story_sentences_id = int(result['value'])

while True:
    r = requests.get( 'http://localhost:8983/solr/collection1/dataimport?command=status&wt=json', headers = { 'Accept': 'application/json'})  
    data = r.json()

    if data['status'] != 'busy':
        print data
        print data['status']

        cursor.execute("UPDATE database_variables set value = %(value)s where name = %(name)s ", 
                   { 'name': pg_last_import_id_var, 'value': min_story_sentences_id - 1 } )
        

        cursor.execute(
            """UPDATE story_sentences set db_row_last_updated = now() where """ 
            """ story_sentences_id > (select value::integer from database_variables where name = %s ) """ 
            """and story_sentences_id <= (select value::integer from database_variables where name = %s ) + 1000000 """,
            (  pg_last_import_id_var,  pg_last_import_id_var) )

        conn.commit

        print "importing with min_story_sentences_id {} ...".format( min_story_sentences_id )

        min_story_sentences_id += 1000000

        requests.get( 'http://localhost:8983/solr/collection1/dataimport?command=full-import&commit=true&clean=false' )
    else:
        print "import busy"

    print "sleeping"

    time.sleep( 20 )
