#!/usr/bin/python
import choice
import mc_solr

confirm = choice.Binary('Warning: A full import will delete all data from solr and then reimport from Postgresql\n' +  'Are you sure you want to do this?', False).ask()

if confirm:
    print mc_solr.dataimport_full_import()

