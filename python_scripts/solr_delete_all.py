#!/usr/bin/python
import choice
import mc_solr

confirm = choice.Binary("This will delete all documents in the Solr database\n" +
                        'Are you sure you want to do this?', False).ask()

if confirm:
    print mc_solr.delete_all_documents()

