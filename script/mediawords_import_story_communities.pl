#!/usr/bin/env perl

# import csv of media source communities as story tags within a controversy

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Util::CSV;
use MediaWords::Util::Tags;

sub add_community_tag_to_stories
{
    my ( $db, $controversies_id, $media_id, $community_id ) = @_;

    die( "no media_id" ) unless ( defined( $media_id ) );

    die( "no community_id" ) unless ( defined( $community_id ) );

    my $community_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "cc_communities:community_${ community_id }" );

    $db->query( <<SQL, $community_tag->{ tags_id }, $controversies_id, $media_id );
insert into stories_tags_map
    ( stories_id, tags_id )
    select s.stories_id, \$1
        from cd.live_stories s
        where controversies_id = \$2 and media_id = \$3 and
            not exists (
                select 1 from stories_tags_map stm
                    where stm.stories_id = s.stories_id and stm.tags_id = \$1
            )
SQL
}

sub main
{
    my ( $csv, $controversies_id ) = @ARGV;

    die( "usage: $0 <csv> <controversies_id>" ) unless ( $csv && $controversies_id );

    my $db = MediaWords::DB::connect_to_db;

    my $media_communities = MediaWords::Util::CSV::get_csv_as_hashes( $csv, 1 );

    my $num_mc = scalar( @{ $media_communities } );
    my $i      = 1;
    for my $mc ( @{ $media_communities } )
    {
        say STDERR $i++ . " / $num_mc";
        add_community_tag_to_stories( $db, $controversies_id, $mc->{ id }, $mc->{ modularity_class } );
    }
}
main();
