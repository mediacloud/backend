#!/usr/bin/env perl
use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::CommonLibs;
use Modern::Perl "2013";
use SNA::Network;
use Encode;
use XML::FeedPP;
use Data::Dumper;
use MediaWords::DB;
use List::Util qw(first);
use List::MoreUtils qw(firstidx);
use MediaWords::Controller::Admin::CM;
use Text::CSV;
use CGI qw(:standard);

sub main
{
    my $db = MediaWords::DB::connect_to_db;
    my ( $cdts_id ) = @ARGV;
    my ( $cdts, $cd, $controversy ) = MediaWords::Controller::Admin::CM::_get_controversy_objects( $db, $cdts_id );
    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, 1 );
    my $media   = $db->query( "SELECT * FROM dump_medium_links" )->hashes;
    my $file_no = scalar( @{ $media } );

    my $net = SNA::Network->new();

    my @array  = ();
    my @array2 = ();
    my @in_ar  = ();
    my @in_ar2 = ();
    my $k      = 0;
    my %h1     = ();
    my %h2     = ();

    for ( my $i = 0 ; $i < $file_no ; $i = $i + 1 )
    {
        my $source_mediaid = $media->[ $i ]->{ 'source_media_id' };
        my $source_name    = $media->[ $i ]->{ 'name' };
        my $refid          = $media->[ $i ]->{ 'ref_media_id' };

        if ( !( $source_mediaid ~~ @array ) )
        {
            $in_ar[ $i ] = $k;
            $net->create_node_at_index( index => $k, name => $source_mediaid );
            $h1{ $source_mediaid } = $k;
            $k                     = $k + 1;
            $array[ $i ]           = $media->[ $i ]->{ 'source_media_id' };
        }
        else
        {
            $in_ar[ $i ] = $k - 1;
            $array[ $i ] = 0;
        }
    }
    my $j = $k;

    for ( my $i = 0 ; $i < $file_no ; $i = $i + 1 )
    {
        my $source_mediaid = $media->[ $i ]->{ 'source_media_id' };
        my $target_mediaid = $media->[ $i ]->{ 'ref_media_id' };

        if ( !( $target_mediaid ~~ @array2 ) and !( $target_mediaid ~~ @array ) )
        {

            $in_ar2[ $i ] = $j;
            $net->create_node_at_index( index => $j, name => $target_mediaid );
            $h2{ $target_mediaid } = $j;
            $j                     = $j + 1;
            $array2[ $i ]          = $media->[ $i ]->{ 'ref_media_id' };
        }
        elsif ( $target_mediaid ~~ @array )
        {
            if ( exists $h1{ $target_mediaid } )
            {
                $in_ar2[ $i ] = $h1{ $target_mediaid };
            }

            $array2[ $i ] = 0;
        }
        else
        {
            if ( exists $h2{ $target_mediaid } )
            {
                $in_ar2[ $i ] = $h2{ $target_mediaid };
            }
            $array2[ $i ] = 0;
        }
    }
    for ( my $i = 0 ; $i < $file_no ; $i = $i + 1 )
    {
        my $source_mediaid = $media->[ $i ]->{ 'source_media_id' };
        my $target_mediaid = $media->[ $i ]->{ 'ref_media_id' };
        $net->create_edge( source_index => $in_ar[ $i ], target_index => $in_ar2[ $i ], weight => 1.0 );
    }
    my $num_communities = $net->identify_communities_with_louvain;
    foreach my $community ( $net->communities )
    {
        foreach my $member ( $community->members )
        {
            say "Media_url/name:" . Dumper( $member->{ 'index' } ), "Community-id: ", $community->index, "\n";
        }
    }

}
main();
