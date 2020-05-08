#!/usr/bin/env perl

# dump solr query as csv

use strict;
use warnings;

use Encode;
use File::Slurp;
use Text::CSV_XS;

use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::Solr;
use List::MoreUtils qw/natatime/;

sub main
{
    my ( $q, $fq ) = @ARGV;

    die( "usage: $0 <solr query> [<solr filter query>]" ) unless ( $q );

    if ( $q =~ /\.txt$/ )
    {
        $q = File::Slurp::read_file( $q );
    }

    my $db = MediaWords::DB::connect_to_db();

    my $stories_ids = MediaWords::Solr::search_solr_for_stories_ids( $db, { q => $q, fq => $fq, rows => 10_000_000 } );

    print STDERR "found " . scalar( @{ $stories_ids } ) . " stories\n";

    my $fields = [ qw/stories_id title url publish_date media_id media_name media_url/ ];
    if ( $q =~ /timespans_id:(\d+)/ )
    { 
        push( @{ $fields }, qw/media_inlink_count inlink_count outlink_count facebook_share_count/ ); 
    } 

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    $csv->combine( @{ $fields } );

    print( Encode::encode( 'utf-8', $csv->string() . "\n" ) );

    my $i = 1;
    my $iter = natatime( 1000, @{ $stories_ids } );
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
        if ( $q =~ /timespans_id:(\d+)/ ) 
        { 
			my $timespans_id = $1;
            my $slc = $db->query( <<SQL, $timespans_id )->hashes; 
select slc.* from snap.story_link_counts slc
    where timespans_id = ? and stories_id in ( select id from $ids_table ) 
SQL
            MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $slc ); 
        } 

        for my $story ( @{ $stories } )
        {
            $csv->combine( map { $story->{ $_ } } @{ $fields } );
            print( Encode::encode( 'utf-8', $csv->string() . "\n" ) );
        }
    }
}

main();
