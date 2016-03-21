#!/usr/bin/env perl

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib", "$FindBin::Bin";
}

use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use DBI;
use DBIx::Simple;
use DBIx::Simple::MediaWords;
use URI::Escape;
use List::Uniq ':all';
use List::Util qw (max min reduce sum);
use List::Pairwise qw(mapp grepp map_pairwise);
use URI;
use URI::Split;
use Data::Dumper;
use Array::Compare;
use Hash::Merge;
use Carp;
use Readonly;
use TableCreationUtils;
use XML::LibXML;

my $count_queries = {
    non_spidered_hosts        => "select count(*) from non_spidered_hosts;",
    found_blogs               => "select count(*) from found_blogs;",
    found_blogs_LJ            => "select count(*) from found_blogs where site ='livejournal.com';",
    found_blogs_Live_Internet => "select count(*) from found_blogs where site ='liveinternet.ru';",
    found_blogs_Diary_Ru      => "select count(*) from found_blogs where site ='diary.ru';",
    found_blogs_loveplanet    => "select count(*) from found_blogs where site ='loveplanet.ru';",
    found_blogs_mail_ru       => "select count(*) from found_blogs where site ='mail.ru';",
    found_blogs_privet_ru     => "select count(*) from found_blogs where site ='privet.ru';",
    rejected_blogs            => "select count(*) from rejected_blogs;",
    non_blog_host_links       => "select count(*) from non_blog_host_links;",
    downloads                 => "select count(*) from downloads;",
    downloads_pending         => "select count(*) from downloads where state='pending';",
    downloads_success         => "select count(*) from downloads where state='success';",
    found_urls_new => "select num_urls from url_discovery_counts where url_discovery_status = 'not_yet_processed'",
    found_urls_old => "select num_urls from url_discovery_counts where url_discovery_status = 'already_processed'",
    found_url_ratio =>
"select round(num_already_processed::numeric/num_not_yet_processed::numeric, 3) from (select num_urls as num_already_processed from url_discovery_counts where url_discovery_status = 'already_processed') as foo, (select num_urls as num_not_yet_processed from url_discovery_counts where url_discovery_status = 'not_yet_processed') as bar;",
};

sub get_results_element
{
    my $db      = TableCreationUtils::get_database_handle();
    my $results = XML::LibXML::Element->new( 'results' );

    while ( my ( $value, $query ) = each( %$count_queries ) )
    {

        #   my $downloads_count = $db->query("select count(*)  as downloads_count from downloads;")->flat->[0];
        #  $results->appendTextChild('downloads_count', $downloads_count);

        my $downloads_count = $db->query( $query )->flat->[ 0 ];
        $results->appendTextChild( $value, $downloads_count );
    }

    my $time = time();

    $results->setAttribute( 'time', $time );

    return $results;
}

sub main
{

    my $xml_file_name = shift( @ARGV );

    die "Must specify file name" unless $xml_file_name;

    my $doc;

    my $historical_results;

    if ( open my $fh, $xml_file_name )
    {
        binmode $fh;    # drop all PerlIO layers possibly created by a use open pragma
        my $parser = XML::LibXML->new;
        $doc = $parser->parse_fh( $fh );
        $historical_results = $doc->documentElement() || die;
    }
    else
    {
        $doc                = XML::LibXML::Document->new();
        $historical_results = $doc->createElement( 'historical_results' );
        $doc->setDocumentElement( $historical_results );

        #print "Creating file\n";
        #exit;
    }

    my $results = get_results_element();

    $historical_results->appendChild( $results );

    $doc->toFile( $xml_file_name, 1 );

}

main();
