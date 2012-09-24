MediaCloud Python API Client
============================

This module is an simple *under construction* demonstration MediaCloud api client written 
in Python.  It demonstrates pulling stories via the MediaCloud API, processing them via an 
event subscription to add metadata, and storing all the metadata to a CouchDB document 
database.

Installation
------------

Make sure you have Python > 2.6 (and setuptools) and then install the python dependencies:
    
    easy_install -Z pypubsub
    easy_install nltk
    easy_install couchdb
    
Install and run CouchDB to store article info (created a 'mediacloud' database):

    http://couchdb.apache.org

Copy the `mc-client.config.template` to `mc-client.config` and edit it, putting in the 
API username and password.

### Ubuntu

On Ubuntu, you may need to do this first to get nltk to install:

  sudo aptitude install python-dev
  

Testing
-------

To verify it all works, run the `test.py` script:

    python test.py 

Examples
--------

Run the `example_word_counts.py` script to populate your database with recent stories, 
including a column that is the total number of words in the extracted text received via
the API.
