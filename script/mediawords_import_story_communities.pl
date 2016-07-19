#!/usr/bin/env perl

# import csv of media source communities as story tags within a topic

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
    my ( $db, $topics_id, $media_id, $community_id ) = @_;

    die( "no media_id" ) unless ( defined( $media_id ) );

    die( "no community_id" ) unless ( defined( $community_id ) );

    my $community_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "cc_communities:community_${ community_id }" );

    $db->query( <<SQL, $community_tag->{ tags_id }, $topics_id, $media_id );
insert into stories_tags_map
    ( stories_id, tags_id )
    select s.stories_id, \$1
        from snap.live_stories s
        where topics_id = \$2 and media_id = \$3 and
            not exists (
                select 1 from stories_tags_map stm
                    where stm.stories_id = s.stories_id and stm.tags_id = \$1
            )
SQL
}

sub main
{
    my ( $csv, $topics_id ) = @ARGV;

    die( "usage: $0 <csv> <topics_id>" ) unless ( $csv && $topics_id );

    my $db = MediaWords::DB::connect_to_db;

    my $media_communities = MediaWords::Util::CSV::get_csv_as_hashes( $csv, 1 );

    my $num_mc = scalar( @{ $media_communities } );
    my $i      = 1;
    for my $mc ( @{ $media_communities } )
    {
        say STDERR $i++ . " / $num_mc";
        add_community_tag_to_stories( $db, $topics_id, $mc->{ id }, $mc->{ modularity_class } );
    }
}
main();
