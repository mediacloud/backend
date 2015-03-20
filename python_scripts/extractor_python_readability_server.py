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
import readability


def extract_with_python_readability( raw_content ):
    doc = readability.Document( raw_content )
    
    return [ u'' + doc.short_title(),
             u'' + doc.summary() ]

class ExtractorHandler:
    def extract_html( self, raw_html ):
        ret = extract_with_python_readability( raw_html )
        return ret

handler = ExtractorHandler()
processor = ExtractorService.Processor(handler)
listening_socket = TSocket.TServerSocket(port=9090)
tfactory = TTransport.TBufferedTransportFactory()
pfactory = TBinaryProtocol.TBinaryProtocolFactory()

server = TProcessPoolServer(processor, listening_socket, tfactory, pfactory)
server.setNumWorkers( 30 )
print ("[Server] Started")
server.serve()
