#!/usr/bin/env perl

use strict;
use warnings;

# test MediaWords::Solr::_get_stories_ids_from_stories_only_params, which
# does simple parsing of solr queries to find out if there is only a list of
# stories_ids, in which case it just returns the story ids directly

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use English '-no_match_vars';

use Data::Dumper;
use Test::More;
use Test::Deep;

BEGIN
{
    use_ok( 'MediaWords::Solr' );
}

# run the given set of params against _gsifsop and verify that the
# given list of stories_ids (or undef) is returned
sub test_query
{
    my ( $params, $expected_stories_ids, $label ) = @_;

    my $got_stories_ids = MediaWords::Solr::_get_stories_ids_from_stories_only_params( $params );

    if ( $expected_stories_ids )
    {
        ok( $got_stories_ids, "$label stories_ids defined" );
        return unless ( $got_stories_ids );

        is( scalar( @{ $got_stories_ids } ), scalar( @{ $expected_stories_ids } ), "$label expected story count" );

        my $got_story_lookup = {};
        map { $got_story_lookup->{ $_ } = 1 } @{ $got_stories_ids };

        map { ok( $got_story_lookup->{ $_ }, "$label: expected stories_id $_" ) } @{ $expected_stories_ids };
    }
    else
    {
        is( $got_stories_ids, undef, "$label: expected undef" );
    }
}

sub main
{
    test_query( { q  => '' }, undef, 'empty q' );
    test_query( { fq => '' }, undef, 'empty fq' );
    test_query( { q => '', fq => '' }, undef, 'empty q and fq' );
    test_query( { q => '', fq => '' }, undef, 'empty q and fq' );

    test_query( { q => 'stories_id:1' }, [ 1 ], 'simple q match' );
    test_query( { q => 'media_id:1' }, undef, 'simple q miss' );
    test_query( { q => '*:*', fq => 'stories_id:1' }, [ 1 ], 'simple fq match' );
    test_query( { q => '*:*', fq => 'media_id:1' }, undef, 'simple fq miss' );

    test_query( { q => 'media_id:1',   fq => 'stories_id:1' }, undef, 'q hit / fq miss' );
    test_query( { q => 'stories_id:1', fq => 'media_id:1' },   undef, 'q miss / fq hit' );

    test_query( { q => '*:*', fq => [ 'stories_id:1', 'stories_id:1' ] }, [ 1 ], 'fq list hit' );
    test_query( { q => '*:*', fq => [ 'stories_id:1', 'media_id:1' ] }, undef, 'fq list miss' );

    test_query( { q => 'stories_id:1', fq => '' },             [ 1 ], 'q hit / empty fq' );
    test_query( { q => 'stories_id:1', fq => [] },             [ 1 ], 'q hit / empty fq list' );
    test_query( { q => '*:*',          fq => 'stories_id:1' }, [ 1 ], '*:* q / fq hit' );
    test_query( { fq => 'stories_id:1' }, undef, 'empty q, fq hit' );
    test_query( { q  => '*:*' },          undef, '*:* q' );

    test_query( { q => 'stories_id:( 1 2 3 )' }, [ 1, 2, 3 ], 'q list' );
    test_query( { q => 'stories_id:( 1 2 3 )', fq => 'stories_id:( 1 3 4 )' }, [ 1, 3 ], 'q list / fq list intersection' );
    test_query( { q => '( stories_id:2 )' }, [ 2 ], 'q parens' );
    test_query( { q => '(stories_id:3)' },   [ 3 ], 'q parens no spaces' );

    test_query( { q => 'stories_id:4 and stories_id:4' }, [ 4 ], 'q simple and' );
    test_query( { q => 'stories_id:( 1 2 3 ) and stories_id:( 2 3 4 )' }, [ 2, 3 ], 'q and intersection' );
    test_query( { q => 'stories_id:( 1 2 3 ) and stories_id:( 4 5 6 )' }, [], 'q and empty intersection' );

    test_query(
        { q => 'stories_id:( 1 2 3 4 ) and ( stories_id:( 2 3 4 5 6 ) and stories_id:( 3 4 ) )' },
        [ 3, 4 ],
        'q complex and intersection'
    );
    test_query( { q => 'stories_id:( 1 2 3 4 ) and ( stories_id:( 2 3 4 5 6 ) and media_id:1 )' },
        undef, 'q complex and intersection miss' );
    test_query( { q => 'stories_id:( 1 2 3 4 ) and ( stories_id:( 2 3 4 5 6 ) and stories_id:( 243 ) )' },
        [], 'q complex and intersection empty' );
    test_query(
        { q => 'stories_id:( 1 2 3 4 ) and stories_id:( 2 3 4 5 6 ) and stories_id:( 3 4 )' },
        [ 3, 4 ],
        'q complex and intersection'
    );

    test_query( { q => 'stories_id:1 and ( stories_id:2 and ( stories_id:3 and obama ) )' },
        undef, 'q complex boolean query with buried miss' );
    test_query( { q => '( ( stories_id:1 or stories_id:2 ) and stories_id:3 )' },
        undef, 'q complex boolean query with buried or' );

    test_query( { q => 'stories_id:( 1 2 3 4 5 6 )', foo => 'bar' }, undef, 'unrecognized parameters' );
    test_query( { q => 'stories_id:( 1 2 3 4 5 6 )', start => '2' }, [ 3, 4, 5, 6 ], 'start parameter' );
    test_query( { q => 'stories_id:( 1 2 3 4 5 6 )', start => '2', rows => 2 }, [ 3, 4 ], 'start and rows parameter' );
    test_query( { q => 'stories_id:( 1 2 3 4 5 6 )', rows => 2 }, [ 1, 2 ], 'rows parameter' );

    done_testing;
}

main();
