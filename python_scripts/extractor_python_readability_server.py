#!/usr/bin/python

import sys
import glob
sys.path.append("python_scripts/gen-py")
sys.path.append("gen-py/thrift_solr/")

from thrift.transport import TSocket 
from thrift.server import TServer 
#import thrift_solr
import ExtractorService

import sys

import readability

import readability

def extract_with_python_readability( raw_content ):
    doc = readability.Document( raw_content )
    
    return [ u'' + doc.short_title(),
             u'' + doc.summary() ]

class ExtractorHandler:
    def extract_html( self, raw_html ):

        print raw_html

        #raw_html = raw_html.encode( 'utf-8' )

        ret =  extract_with_python_readability( raw_html )
        print ret[1]
        return ret

handler = ExtractorHandler()
processor = ExtractorService.Processor(handler)
listening_socket = TSocket.TServerSocket(port=9090)
server = TServer.TThreadPoolServer(processor, listening_socket)

print ("[Server] Started")
server.serve()
