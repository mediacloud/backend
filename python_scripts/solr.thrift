namespace java thrift_solr
namespace py thrift_solr
namespace perl thrift_solr

service SolrService {
   map< string, i32 > media_counts( 1:string q, 2:string facet_field, 3:list<string> fq, 4:i32 mincount )
} 
  