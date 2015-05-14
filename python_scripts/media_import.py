# -*- coding: utf-8 -*-
# <nbformat>3.0</nbformat>

# <codecell>

import cPickle
import os.path

api_key = cPickle.load( file( os.path.expanduser( '~/mediacloud_api_key.pickle' ), 'r' ) )

import cPickle
import os.path
from prompter import yesno

cPickle.dump( api_key, file( os.path.expanduser( '~/mediacloud_api_key.pickle' ), 'wb' ) )

import sys
#print (sys.path)
#sys.path.append('../')
#sys.path
import mc_database

# <codecell>

import psycopg2
import psycopg2.extras

# <codecell>

import mediacloud, json


# <codecell>

def cast_fields_to_bool( dict_obj, fields ):
    for field in fields:
        if dict_obj[ field ] is not None:
            dict_obj[ field ] = bool( dict_obj[field])

    

# <codecell>

def non_list_pairs( item ):
    item = { k: item[k]  for k in  item.keys() if type(item[k]) != list  }
    return item

def insert_into_table( cursor, table_name, item ):
    item = { k: item[k]  for k in  item.keys() if type(item[k]) != list  }
    columns = ', '.join(item.keys())
    
    placeholders = ', '.join([ '%('+ c + ')s'  for c in item.keys() ])
    
    query = "insert into " + table_name + " (%s) Values (%s)" %( columns, placeholders)
    #print query
    cursor.execute( query , item )

# <codecell>

def update_db_sequences( conn ):
    cursor = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    cursor.execute( "select setval(pg_get_serial_sequence('tag_sets', 'tag_sets_id'), (select max(tag_sets_id)+1 from tag_sets))" )
    
    cursor.execute( "select setval(pg_get_serial_sequence('tags', 'tags_id'), (select max(tags_id)+1 from tags))" )
    cursor.execute( "select setval(pg_get_serial_sequence('media', 'media_id'), (select max(media_id)+1 from media))" )
    cursor.execute( "select setval(pg_get_serial_sequence('media_sets', 'media_id'), (select max(media_id)+1 from media))" )
    cursor.execute( "select setval(pg_get_serial_sequence('media_sets_media_map', 'media_id'), (select max(media_id)+1 from media))" )
    cursor.execute( "select setval(pg_get_serial_sequence('media_tags_map', 'media_tags_map_id'), (select max(media_tags_map_id)+1 from media_tags_map))" )
    cursor.execute( "select setval(pg_get_serial_sequence('feeds', 'feeds_id'), (select max(feeds_id)+1 from feeds))" )
    
    cursor.execute( "select setval(pg_get_serial_sequence('feeds_tags_map', 'feeds_tags_map_id'), (select max(feeds_tags_map_id)+1 from feeds_tags_map))" )
    
    cursor.close()
    conn.commit()

# <codecell>

def truncate_tables( conn ):
    cursor = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    cursor.execute( "SELECT count(*)  > 10000 as has_many_downloads from downloads")
    rec = cursor.fetchone()
    assert ( not rec['has_many_downloads'])
    
    cursor.execute( "TRUNCATE tag_sets CASCADE " )
    cursor.execute( "TRUNCATE media CASCADE" )
    cursor.execute( "TRUNCATE feeds CASCADE" )
    conn.commit()
        

# <codecell>

def get_tag_sets( mc ):
    all_tag_sets = []

    last_tag_sets_id = 0
    
    while True:
        tag_sets = mc.tagSetList( last_tag_sets_id=last_tag_sets_id, rows=20)
        if len(tag_sets) == 0:
            break
        
        #print tag_sets
        last_tag_sets_id = tag_sets[-1]['tag_sets_id']
        #print last_tag_sets_id
    
         
        all_tag_sets.extend(tag_sets)
        
    return all_tag_sets   

# <codecell>

def add_tag_sets_to_database( conn, all_tag_sets ):
    cursor = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    for tag_set in all_tag_sets:
        cast_fields_to_bool( tag_set, [ 'show_on_media', 'show_on_stories' ] )
        insert_into_table( cursor, 'tag_sets', tag_set )
        print 'inserted ' + tag_set['name']
    conn.commit()    

# <codecell>

def add_media_to_database( conn, all_media ):
    
    cursor = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    cursor.execute( "SET CONSTRAINTS media_dup_media_id_fkey DEFERRED ") 
    
    num_media_inserted = 0
    
    for medium in all_media:
        medium = non_list_pairs( medium)
        #del medium['dup_media_id']
        cast_fields_to_bool( medium, [ 'extract_author', 'annotate_with_corenlp', "full_text_rss",
                                  "foreign_rss_links",  "feeds_added", "moderated", "use_pager", "is_not_dup"])
        insert_into_table( cursor, 'media', medium )
        
        num_media_inserted += 1
        
        if num_media_inserted % 500 == 0:
            print "Inserted " + str( num_media_inserted ) + " out of " + str(len(all_media) )
            
        #print 'inserted '
        
    conn.commit()
    cursor.close()
    conn.commit()

# <codecell>

def get_media( mc ):
    all_media = []

    last_media_id = 0
    
    while True:
        media = mc.mediaList( last_media_id=last_media_id, rows=1000)
        print last_media_id, len( media ), len( all_media )
    
        if len(media) == 0:
            break
            
        last_media_id = media[-1]['media_id']
        last_media_id
        
        all_media.extend(media)
        
        #if len( all_media ) > 10000:
        #    break
    
    return all_media

# <codecell>

def add_feeds_from_media_to_database( conn, mc, media ):
    cursor = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    
    num_media_processed = 0
    
    for medium in media:
        feeds_for_media = mc.feedList( media_id=medium['media_id'], rows=1000)
        assert len( feeds_for_media ) < 1000
        
        for feed in feeds_for_media:
            insert_into_table( cursor, 'feeds', feed )
            
        num_media_processed += 1
        
        if num_media_processed % 1000 == 0:
            print "inserted feeds for " + str( num_media_processed ) + " out of " + str ( len( media ) )
    
    conn.commit()
    cursor.close()
    conn.commit()
    

def main():

    if not yesno('This will erase all data in the current media cloud database. Are you sure you want to continue?'):
        exit()

    mc = mediacloud.api.MediaCloud(api_key, all_fields=True)

    conn = mc_database.connect_to_database()
    print "truncating tables"

    truncate_tables( conn )
    update_db_sequences(conn)
    print "obtaining tag sets"
    all_tag_sets = get_tag_sets( mc )

    print "importing tag sets"
    add_tag_sets_to_database( conn, all_tag_sets )

    print "obtaining media"
    all_media = get_media( mc )

    print "importing media"
    add_media_to_database( conn, all_media )

    print "importing feeds from media"
    add_feeds_from_media_to_database( conn, mc, all_media )

    print "updating sequences"
    update_db_sequences(conn)

if __name__ == "__main__":
    main()
