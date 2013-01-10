#! /usr/bin/env python

import ConfigParser

from mediacloud.storage import CouchStoryDatabase
import mediacloud.examples

'''
This example file creates the views needed by the other example files.  Run it once
to initialize the design document used by all the other examples.
'''

config = ConfigParser.ConfigParser()
config.read('mc-client.config')

# set up a connection to the DB
db = CouchStoryDatabase('mediacloud', config.get('db','host'), config.get('db','port') )

# create the views
db.insertExampleViews()

print "Created the views"