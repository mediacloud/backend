#!/bin/bash

curl http://localhost:8983/solr/collection1/dataimport?command=delta-import&entity=StorySentences&commit=true


