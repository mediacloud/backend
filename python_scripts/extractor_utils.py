#
# A central location for extractor testing routines used in multiple notebooks
#
import mc_config
import psycopg2

import psycopg2.extras

def get_db_info():
    config_file = mc_config.read_config()
    
    db_infos = config_file['database']
    db_info = next (db_info for db_info in db_infos if db_info['port'] == '6000' )
    return db_info


def get_chloe_db_connection():
    db_info = get_db_info()

    conn = psycopg2.connect( database=db_info['db'], user=db_info['user'], 
                             password=db_info['pass'], host=db_info['host'], port=db_info['port'] )

    return conn

