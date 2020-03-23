package MediaWords::Test::Solr;

use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.test.solr' );

use Test::More;

use MediaWords::Solr;

=head2 test_story_query( $db, $q, $expected_story, $label )

Run the given query against solr, adding an 'and stories_id:$expected_story->{ stories_id }' to make it return at
most one story.  Verify that the query succeeds and returns only the $expected_story.

MC_REWRITE_TO_PYTHON: rewritten as "assert_story_query()" in Python; Perl implementation retained intentionally

=cut

sub test_story_query($$$;$)
{
    my ( $db, $q, $expected_story, $label ) = @_;

    $label //= 'test story query';

    my $expected_stories_id = $expected_story->{ stories_id };

    my $r = MediaWords::Solr::query_solr( $db, { q => "$q and stories_id:$expected_stories_id", rows => 1_000_000 } );

    my $docs = $r->{ response }->{ docs };

    die( "no response.docs found in solr results: " . Dumper( $r ) ) unless ( $docs );

    my $got_stories_ids = [ map { $_->{ stories_id } } @{ $docs } ];

    is_deeply( $got_stories_ids, [ $expected_stories_id ], "$label: $q" );
}

1;
