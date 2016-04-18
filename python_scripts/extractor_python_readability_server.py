#!/usr/bin/python

import sys
import os
import glob
sys.path.append(os.path.join(os.path.dirname(__file__),"gen-py/thrift_solr/"))
sys.path.append(os.path.dirname(__file__) )

from thrift.transport import TSocket 
from thrift.transport import TTransport
from thrift.protocol import TBinaryProtocol
from thrift.server import TServer 
from thrift.protocol.TBinaryProtocol import TBinaryProtocolAccelerated
from thrift.server.TProcessPoolServer import TProcessPoolServer

import ExtractorService
import sys
from readability.readability import Document


def extract_with_python_readability( raw_content ):
    doc = Document( raw_content )
    
    return [ u'' + doc.short_title().strip(),
             u'' + doc.summary().strip() ]

class ExtractorHandler:
    def extract_html( self, raw_html ):
        ret = extract_with_python_readability( raw_html )
        return ret

handler = ExtractorHandler()
processor = ExtractorService.Processor(handler)
listening_socket = TSocket.TServerSocket(port=9090)
tfactory = TTransport.TBufferedTransportFactory()
pfactory = TBinaryProtocol.TBinaryProtocolFactory()

# Test the extractor real quick; if it doesn't work, don't proceed to creating the server
test_html = "<html><body><p>Media Cloud</p></body></html>"
extracted_text = handler.extract_html( test_html )
if not extracted_text:
    raise ImportError("'readability' module has been imported, but I'm unable to extract anything with it")

server = TProcessPoolServer(processor, listening_socket, tfactory, pfactory)
server.setNumWorkers( 30 )
print ("[Server] Started")
server.serve()
