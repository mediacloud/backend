#!/usr/bin/python
 
import yaml

def read_config():
    yml_file = open('/home/dlarochelle/git_dev/mediacloud/mediawords.yml', 'rb')
    config_file = yaml.load( yml_file )
    return config_file

