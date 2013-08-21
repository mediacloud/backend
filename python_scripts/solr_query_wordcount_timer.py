#!/usr/bin/python

import requests
import ipdb
import time
import csv
import sys
import pysolr

def _fetch_all( solr, arg1 ) :
    documents = []
    num_matching_documents = solr.search( arg1 ).hits

    start = 0
    rows = num_matching_documents

    sys.stderr.write( ' starting fetch for ' + arg1 )
    if 1==1 :
        results = solr.search( arg1, **{ 
                'start': start,
           #     'rows': rows,
                'facet':"true",
                "facet.limit":"100",
                "facet.field":"includes",
                "facet.method":"enum",
            #    "rows":"0"
               # 'fl' : 'media_id',
                })
     #   documents.extend( results.docs )
        start += rows

     #   assert len( documents ) <= num_matching_documents

    #assert len( documents ) == num_matching_documents
    return results

def time_to_fetch_all( solr, arg1 ) :
    start = time.time()
    _fetch_all( solr, arg1 )
    end = time.time()
    return end - start


url_file = 'urls.txt'

solr = pysolr.Solr('http://localhost:8983/solr/')

queries = [ 'sentence:obama',
            'sentence:mccain', 
            'sentence:snowden', 
            'sentence:trayvon', 
            'sentence:benghazi',
            'sentence:the'
            ]

dates = [
    None,
    'publish_date:[2013-04-01T00:00:00.000Z TO 2013-04-01T00:00:00.000Z+1DAY]',
    'publish_date:[2013-04-01T00:00:00.000Z TO 2013-04-01T00:00:00.000Z+7DAYS]',
    'publish_date:[2013-04-01T00:00:00.000Z TO 2013-04-01T00:00:00.000Z+1MONTH]',
    ]

results = _fetch_all(solr, 'sentence:best');

ipdb.set_trace()

time = time_to_fetch_all(solr, 'sentence:best');

for result in results:
	print("The result is '{0}'.".format(result))
print "time: ", time

#with open('/tmp/query_count.csv', 'wb' ) as csvfile:
#    resultswriter = csv.DictWriter( csvfile, ['query', 'count', 'fetch_time'], extrasaction='ignore' )
#    resultswriter.writeheader()
#    for date in dates:
#        for query in queries:
#            if date:
#                query += " AND " + date

#           results = solr.search(query,  **{ 
#                'fl' : 'id',
#                })

#            hits = results.hits
#            qtime = results.qtime

#            if query.startswith('sentence:the') or query.find(' AND ') == -1 :
#                fetch_time = 'N/A'
#            else:
#                fetch_time = time_to_fetch_all( solr, query )

            #print " {0} hits: {1} time {2} ".format( query, hits, qtime)
#            resultswriter.writerow( { 'query' : query, 'count': hits, 'fetch_time': fetch_time  } )


# with open('/tmp/url_time.csv', 'wb' ) as csvfile:
#     resultswriter = csv.DictWriter( csvfile, ['url', 'qtime', 'total_time'], extrasaction='ignore' )
#     resultswriter.writeheader()
#     for result in results:
#         resultswriter.writerow( result )




# results = []
# sys.stderr.write('Starting')
# with open ( url_file, 'r' ) as f:
#     for url in f:
#         url = url.rstrip()
#         start_time = time.clock()
#         sys.stderr.write( 'requesting ' + url )
#         r = requests.get( url )
#         end_time = time.clock()
#         total_time = end_time = start_time
#         json = r.json()
#         qtime = json['responseHeader']['QTime']

#         result = { 'url' : url, 'qtime' : qtime, 'total_time': total_time,  'json' : json }
#         print "got:"
#         print result
#         results.append( result )

# with open('/tmp/url_time.csv', 'wb' ) as csvfile:
#     resultswriter = csv.DictWriter( csvfile, ['url', 'qtime', 'total_time'], extrasaction='ignore' )
#     resultswriter.writeheader()
#     for result in results:
#         resultswriter.writerow( result )


        

