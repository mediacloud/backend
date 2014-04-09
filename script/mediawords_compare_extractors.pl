#!/usr/bin/env perl

# extract the text for the given story using the heuristic and crf extractors
use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::Util::Config;

sub main
{
    my ( $stories_id ) = @ARGV;

    die( "usage: $0 < stories_id >" ) unless ( $stories_id );

    my $db = MediaWords::DB::connect_to_db;

    my $story = $db->find_by_id( 'stories', $stories_id );
    print Dumper( $story );

    my $downloads = $db->query( "select * from downloads where stories_id = ? order by downloads_id", $stories_id )->hashes;

    my $config = MediaWords::Util::Config::get_config;

    print "HEURISTIC:\n\n";

    $config->{ mediawords }->{ extractor_method } = 'HeuristicExtractor';
    my $h_texts = [];
    for my $download ( @{ $downloads } )
    {
        my $res = MediaWords::DBI::Downloads::extractor_results_for_download( $db, $download );
        push( @{ $h_texts }, join( "\n", map { $res->{ download_lines }->[ $_ ] } @{ $res->{ included_line_numbers } } ) );
        print Dumper( $res->{ included_line_numbers } );

        # for ( my $i = 0; $i < @{ $res->{ scores } }; $i++ )
        # {
        #     print Dumper( $res->{ scores }->[ $i ] );
        #     print $res->{ download_lines }->[ $i ] . "\n";
        # }
    }
    print join( "\n****\n", @{ $h_texts } );
    print "\n\n";

    print "CRF:\n\n";
    $config->{ mediawords }->{ extractor_method } = 'CrfExtractor';
    my $crf_texts = [];
    for my $download ( @{ $downloads } )
    {
        my $res = MediaWords::DBI::Downloads::extractor_results_for_download( $db, $download );
        push( @{ $crf_texts }, join( "\n", map { $res->{ download_lines }->[ $_ ] } @{ $res->{ included_line_numbers } } ) );
        print Dumper( $res->{ included_line_numbers } );

        # print Dumper( $res );
    }
    print join( "\n****\n", @{ $crf_texts } );

    print "\n\n";

}

main();
