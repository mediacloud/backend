import sys
import glob
sys.path.append("python_scripts/gen-py") 

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
server = TServer.TThreadPoolServer(processor, listening_socket)

print ("[Server] Started")
server.serve()
