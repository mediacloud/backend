import sys
import glob
sys.path.append("gen-py") 
#sys.path.append('/home/dlarochelle/git_dev/mediacloud/python_scripts/gen-py')
#sys.path.insert(0, glob.glob('/home/dlarochelle/bin/thrift-0.9.1/lib/py/build/lib.*')[0])

from thrift.transport import TSocket 
from thrift.server import TServer 
import thrift_solr
from thrift_solr import SolrService

import mc_solr
import solr_facets_wrapper

class SolrHandler:
    def media_counts( self, q, facet_field, fq, mincount ):
        solr = mc_solr.py_solr_connection()

        return solr_facets_wrapper.facet_query_counts( solr, q, facet_field, fq, mincount)

handler = SolrHandler()
processor = SolrService.Processor(handler)
listening_socket = TSocket.TServerSocket(port=9090)
server = TServer.TSimpleServer(processor, listening_socket)

print ("[Server] Started")
server.serve()
