namespace java thrift_solr
namespace py thrift_solr
namespace perl thrift_solr

service ExtractorService
{
   list< string >  extract_html( 1:string raw_html )
}
  