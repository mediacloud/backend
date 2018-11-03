#!/usr/bin/env perl

# dump solr query as csv

use strict;
use warnings;

use Text::CSV_XS;

use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Solr;

sub main
{
    my ( $q, $fq ) = @ARGV;

    die( "usage: $0 <solr query> [<solr filter query>]" ) unless ( $q );

    my $db = MediaWords::DB::connect_to_db;

    my $stories_ids = MediaWords::Solr::search_for_stories_ids( $db, { q => $q, fq => $fq, rows => 10_000_000 } );

    print STDERR "found " . scalar( @{ $stories_ids } ) . " stories\n";

    my $fields = [ qw/stories_id title url publish_date media_id media_name media_url/ ];

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    $csv->combine( @{ $fields } );

    print( Encode::encode( 'utf-8', $csv->string() . "\n" ) );

    my $i = 1;
    my $iter = List::MoreUtils::natatime( 1000, @{ $stories_ids } );
    while ( my @chunk_stories_ids = $iter->() )
    {
        print STDERR "printing block " . $i++ . "\n";
        my $ids_table = $db->get_temporary_ids_table( \@chunk_stories_ids );
        my $stories   = $db->query( <<SQL )->hashes;
select s.stories_id, s.title, s.url, s.publish_date, s.media_id, m.name media_name, m.url media_url
    from stories s
        join media m using ( media_id )
        join $ids_table i on ( i.id = s.stories_id )
SQL

        for my $story ( @{ $stories } )
        {
            $csv->combine( map { $story->{ $_ } } @{ $fields } );
            print( Encode::encode( 'utf-8', $csv->string() . "\n" ) );
        }
    }
}

main();
