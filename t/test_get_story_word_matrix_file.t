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

my $_possible_words = [
    qw/all analyzing and are around begin being between bloggers can challenging characterize
      cloud collecting comments competing coverage covered cycles differ different event examine for given how ignored
      into introduce issues local mainstream media mix national news offers online other overall parts patterns
      publications quantitatively questions same shape source sources specific stories storylines stream tens terms the
      these thousands track used way we what where/
];

# get random words
sub add_story_sentences_and_language
{
    my ( $db, $story, $num ) = @_;

    my $language = MediaWords::Languages::Language::language_for_code( 'en' );
    $db->query( "update stories set language = 'en' where stories_id = ?", $story->{ stories_id } );
    $story->{ language } = 'en';

    my $stem_counts = {};
    for my $sentence_num ( 0 .. 9 )
    {
        my $sentence = '';
        for my $word_num ( 0 .. 9 )
        {
            my $word = $_possible_words->[ int( rand( @{ $_possible_words } ) ) ];
            $sentence .= "$word ";

            my $stems = $language->stem( $word );
            $stem_counts->{ $stems->[ 0 ] }++;
        }

        $sentence .= '.';

        my $ss = {
            stories_id      => $story->{ stories_id },
            sentence_number => $sentence_num,
            sentence        => $sentence,
            media_id        => $story->{ media_id },
            publish_date    => $story->{ publish_date },
            language        => 'en'
        };
        $db->create( 'story_sentences', $ss );
    }

    $story->{ expected_stem_count } = $stem_counts;
}

sub assign_stem_vectors_from_matrix_file($$$)
{
    my ( $stories, $matrix_file, $stem_list ) = @_;

    my $fh = FileHandle->new( $matrix_file );

    ok( $fh, "open matrix file" );

    my $stories_lookup = {};
    map { $stories_lookup->{ $_->{ stories_id } } = $_ } @{ $stories };

    while ( my $line = <$fh> )
    {
        chomp( $line );

        my ( $stories_id, @stem_counts ) = split( ',', $line );

        is( scalar( @stem_counts ), scalar( @{ $stem_list } ), "stem counts in file same as size of stem list" );

        my $story = $stories_lookup->{ $stories_id };
        ok( $story, "found stories_id" );

        for my $i ( 0 .. @stem_counts - 1 )
        {
            my $stem  = $stem_list->[ $i ];
            my $count = $stem_counts[ $i ];

            $story->{ got_stem_count }->{ $stem } = $count;
        }
    }

    my $num_missing_stories = grep { !$_->{ got_stem_count } } @{ $stories };
    ok( !$num_missing_stories, "no missing stories in file: found $num_missing_stories" );
}

sub test_story($$)
{
    my ( $story, $stem_list ) = @_;

    my $got_stems      = $story->{ got_stem_count };
    my $expected_stems = $story->{ expected_stem_count };

    for my $stem ( @{ $stem_list } )
    {
        is( $got_stems->{ $stem }, $expected_stems->{ $stem } || 0, "count for $stem for story $story->{ stories_id }" );
    }

    map { delete( $got_stems->{ $_ } ) if ( !$got_stems->{ $_ } || $expected_stems->{ $_ } ) } @{ $stem_list };

    ok( !scalar( keys( %{ $got_stems } ) ), "unexpected stem counts: " . Dumper( $got_stems ) );
}

sub run_tests
{
    my ( $db ) = @_;

    my $data = { A => { B => [ ( 1 .. 10 ) ] }, };

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, $data );

    my $stories = [ values( %{ $media->{ A }->{ feeds }->{ B }->{ stories } } ) ];

    map { add_story_sentences_and_language( $db, $_ ) } @{ $stories };

    my $stories_ids = [ map { $_->{ stories_id } } @{ $stories } ];

    my ( $matrix_file, $stem_list ) = MediaWords::DBI::Stories::get_story_word_matrix_file( $db, $stories_ids, 0 );

    assign_stem_vectors_from_matrix_file( $stories, $matrix_file, $stem_list );

    map { test_story( $_, $stem_list ) } @{ $stories };
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
