#
# A central location for extractor testing routines used in multiple notebooks
#
import mc_config
import psycopg2

import psycopg2.extras

def get_db_info( db_label=None):
    config_file = mc_config.read_config()

    databases = config_file['database']

    if db_label is not None:
        databases = [ db for db in databases if db['label'] == db_label ]

    ret = databases[ 0 ]

    return ret

def connect_to_database( db_label=None ):
    db_info = get_db_info( db_label)
    conn = psycopg2.connect( database=db_info['db'], user=db_info['user'], password=db_info['pass'], host=db_info['host'], port=db_info['port'] )
    return conn
