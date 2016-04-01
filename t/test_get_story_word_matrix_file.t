#!/usr/bin/env perl

use strict;
use warnings;

# test MediaWords::DBI::Stories::get_story_word_matrix_file

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Test::More;

BEGIN
{
    use_ok( 'MediaWords::DB' );
    use_ok( 'MediaWords::DBI::Stories' );
    use_ok( 'MediaWords::Test::DB' );
}

my $possible_words = qw/a
all
analyzing
and
are
around
begin
being
between
bloggers
by
can
challenging
characterize
cloud
collecting
comments
competing
coverage
covered
cycles
differ
different
do
event
examine
for
given
how
ignored
in
into
introduce
issues
local
mainstream
media
mix
national
news
of
offers
online
or
other
overall
parts
patterns
publications
quantitatively
questions
same
shape
source
sources
specific
stories
storylines
stream
tens
terms
the
these
thousands
to
track
used
way
we
what
where/;

sub test_is_new
{
    my ( $db, $label, $expected_is_new, $base_story, $story_changes ) = @_;

    my $story = { %{ $base_story } };

    while ( my ( $k, $v ) = each( %{ $story_changes } ) )
    {
        $story->{ $k } = $v;
    }

    my $is_new = MediaWords::DBI::Stories::is_new( $db, $story );

    ok( $expected_is_new ? $is_new : !$is_new, $label );
}

sub test_story
{
    my ( $db, $story, $num ) = @_;

    my $publish_date   = $story->{ publish_date };
    my $plus_two_days  = MediaWords::Util::SQL::increment_day( $publish_date, 2 );
    my $minus_two_days = MediaWords::Util::SQL::increment_day( $publish_date, -2 );

    test_is_new( $db, "$num identical", 0, $story );

    test_is_new( $db, "$num media_id diff",             1, $story, { media_id => $story->{ media_id } + 1 } );
    test_is_new( $db, "$num url+guid diff, title same", 0, $story, { url      => "diff", guid => "diff" } );
    test_is_new( $db, "$num title+url diff, guid same", 0, $story, { url      => "diff", title => "diff" } );
    test_is_new( $db, "$num title+guid diff, url same", 1, $story, { guid     => "diff", title => "diff" } );

    test_is_new( $db, "$num date +2days", 1, $story, { url => "diff", guid => "diff", publish_date => $plus_two_days } );
    test_is_new( $db, "$num date -2days", 1, $story, { url => "diff", guid => "diff", publish_date => $minus_two_days } );
}

# get random words
sub add_story_sentences
{
    my ( $db, $story, $num ) = @_;

    # RESTART - create english langauge object and add stemming below
    my $langauge = MediaWords

    my $stem_counts = {};
    for my $sentence_num ( 0 .. 4 )
    {
        my $sentence = '';
        for my $word_num ( 0 .. 9 )
        {
            my $word = $_possible_words->[ int( rand( @{ $possible_words } ) ) ];
            $sentence .= "$word ";


        }

        $sentence .= '.';

        my $ss = {
            stories_id => $story->{ stories_id },
            sentence_number => $sentence_num,
            sentence => $sentence,
            media_id => $story->{ media_id },
            publish_date => $story->{ publish_date },
            language => 'en'
        };
        $db->create( 'story_sentences', $ss );
    }

}

sub run_tests
{
    my ( $db ) = @_;

    my $data = {
        A => {
            B => [ 1, 2, 3, 4, 5 ]
        },
    };

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, $data );

    my $stories = $media->{ A }->{ feeds }->{ B }->{ stories };

    while ( my ( $num, $story ) = each( %{ $stories } ) )
    {
        add_story_sentences( $db, $story, $num );
        test_story( $db, $story, $num );
    }
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            use Encode;
            my ( $db ) = @_;

            run_tests( $db );
        }
    );

    done_testing();
}

main();
