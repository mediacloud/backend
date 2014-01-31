#!/usr/bin/python
 
import yaml
import os.path

_config_file_base_name = 'mediawords.yml'
_config_file_name = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'mediawords.yml'))

def read_config():
    yml_file = open(_config_file_name, 'rb')
    config_file = yaml.load( yml_file )
    return config_file

