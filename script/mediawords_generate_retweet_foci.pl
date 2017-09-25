#!/usr/bin/env perl

# generate focus definitions for the retweet partisanship tags for the given topic.  remove all other focus definitoins.

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::TM;

Readonly my $MASS_MARKET_MEDIA =>
'2 1 1095 18268 27502 18364 1040 1150 1751 1149 39000 64866 40944 1110 25499 1752 1092 104828 1707 19334 6 1096 1117 6218 4425 62926 8 4442 1757 1112 101 5915 18710 6443 1109 1101 18775 7 113 19984 209366 111 1747 1100 1104 21511 4419 1755 20982 21936 5521';

sub add_mass_market_focus($$)
{
    my ( $db, $topic ) = @_;

    my $fsd = {
        name            => 'Mass Market Media',
        focal_technique => 'Boolean Query',
        topics_id       => $topic->{ topics_id }
    };
    $fsd = $db->create( 'focal_set_definitions', $fsd );

    my $fd = {
        name                     => 'Mass Market Media',
        focal_set_definitions_id => $fsd->{ focal_set_definitions_id },
        arguments                => '{ "query": "-media_id:( ' . $MASS_MARKET_MEDIA . ' )" }'
    };
    $fd = $db->create( 'focus_definitions', $fd );
}

sub add_clinton_foundation_focus($$)
{
    my ( $db, $topic ) = @_;

    my $fsd = {
        name            => 'Clinton Foundation',
        focal_technique => 'Boolean Query',
        topics_id       => $topic->{ topics_id }
    };
    $fsd = $db->create( 'focal_set_definitions', $fsd );

    my $fd = {
        name                     => 'Clinton Foundation',
        focal_set_definitions_id => $fsd->{ focal_set_definitions_id },
        arguments                => '{ "query": "clinton and foundation and -media_id:18346" }'
    };
    $fd = $db->create( 'focus_definitions', $fd );
}

sub add_no_twitter_focus($$)
{
    my ( $db, $topic ) = @_;

    my $fsd_notwitter = {
        name            => 'No Twitter',
        focal_technique => 'Boolean Query',
        topics_id       => $topic->{ topics_id }
    };
    $fsd_notwitter = $db->create( 'focal_set_definitions', $fsd_notwitter );

    my $fd_notwitter = {
        name                     => 'No Twitter',
        focal_set_definitions_id => $fsd_notwitter->{ focal_set_definitions_id },
        arguments                => '{ "query": "-media_id:18346" }'
    };
    $fd_notwitter = $db->create( 'focus_definitions', $fd_notwitter );
}

sub add_quintile_foci($$)
{
    my ( $db, $topic ) = @_;

    my $fsd_quintiles = {
        name            => 'Retweet Partisanship Quintiles',
        focal_technique => 'Boolean Query',
        topics_id       => $topic->{ topics_id }
    };
    $fsd_quintiles = $db->create( 'focal_set_definitions', $fsd_quintiles );

    my $retweet_tags = $db->query( <<SQL )->hashes;
select t.*
    from tags t
        join tag_sets ts using ( tag_sets_id )
    where
        ts.name = 'retweet_partisanship_2016_count_10'
SQL

    die( "retweet partisanship tags not found" ) unless ( @{ $retweet_tags } );

    for my $tag ( @{ $retweet_tags } )
    {
        my $media_ids = $db->query( <<SQL, $tag->{ tags_id } )->flat;
select media_id from media_tags_map where tags_id = \$1
SQL
        my $media_ids_list = join( ' ', @{ $media_ids } );
        my $query = "media_id:(  $media_ids_list )";

        my $tag_fd = {
            name                     => $tag->{ label },
            focal_set_definitions_id => $fsd_quintiles->{ focal_set_definitions_id },
            arguments                => "{ \"query\": \"$query\" }"
        };

        $db->create( 'focus_definitions', $tag_fd );
    }
}

sub add_leftright_foci($$)
{
    my ( $db, $topic ) = @_;

    my $fsd = {
        name            => 'Retweet Partisanship Halves',
        focal_technique => 'Boolean Query',
        topics_id       => $topic->{ topics_id }
    };
    $fsd = $db->create( 'focal_set_definitions', $fsd );

    my $leftright_definitions = [
        { name => 'Right Half', quintiles => [ qw/right center_right center/ ] },
        { name => 'Left Half',  quintiles => [ qw/right center_right center/ ] },
    ];

    for my $d ( @{ $leftright_definitions } )
    {
        my $tags_list = join( ', ', map { $db->quote( $_ ) } @{ $d->{ quintiles } } );

        my $media_ids = $db->query( <<SQL )->flat;
select distinct media_id
    from media_tags_map mtm
        join tags t using ( tags_id )
        join tag_sets ts using ( tag_sets_id )
    where
        ts.name = 'retweet_partisanship_2016_count_10' and
        t.tag in ( $tags_list )
SQL

        my $media_ids_list = join( ' ', @{ $media_ids } );

        my $fd = {
            name                     => $d->{ name },
            focal_set_definitions_id => $fsd->{ focal_set_definitions_id },
            arguments                => '{ "query": "media_id:( ' . $media_ids_list . ' )"}'
        };
        $db->create( 'focus_definitions', $fd );
    }
}

sub main
{
    my ( $topic_opt ) = @ARGV;

    die( "usage: $@ <topic_opt>" ) unless ( $topic_opt );

    my $db = MediaWords::DB::connect_to_db;

    my $topics = MediaWords::TM::require_topics_by_opt( $db, $topic_opt );
    unless ( $topics )
    {
        die "Unable to find topics for option '$topic_opt'";
    }

    for my $topic ( @{ $topics } )
    {
        $db->begin;

        $db->query( "delete from focal_set_definitions where topics_id = \$1", $topic->{ topics_id } );

        add_mass_market_focus( $db, $topic );
        add_no_twitter_focus( $db, $topic );
        add_clinton_foundation_focus( $db, $topic );
        add_quintile_foci( $db, $topic );

        add_leftright_foci( $db, $topic );

        $db->commit;
    }

}

main();
