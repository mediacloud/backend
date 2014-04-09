#!/usr/bin/python
 
import yaml
import os.path

_config_file_base_name = 'mediawords.yml'
_config_file_name = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'mediawords.yml'))

_defaults_config_file_base_name = 'defaults.yml'
_defaults_config_file_name = os.path.abspath(os.path.join(os.path.dirname(__file__), '../config', _defaults_config_file_base_name))


def _load_yml( file_path ):
    yml_file = open(file_path, 'rb')
    config_file = yaml.load( yml_file )
    
    return config_file

def deep_merge( original, update ):
    for key, value in update.iteritems():
        if not key in original:
            original[ key ] = value
        elif isinstance( value, dict) and isinstance( original[key], dict):
            deep_merge( original[ key ], value )

    return original

def read_config():
    
    config_file   = _load_yml( _config_file_name )
    defaults_file = _load_yml( _defaults_config_file_name )

    # print "config_file"
    # print config_file
    # print "defaults_file"
    # print defaults_file
    
    config_file = deep_merge( config_file, defaults_file )    

    # print "Merged"
    # print config_file

    return config_file

