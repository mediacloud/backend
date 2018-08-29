use strict;
use warnings;

use Test::More tests => 13;
use Test::NoWarnings;

use MediaWords::CommonLibs;

use Data::Dumper;
use MediaWords::Test::DB;
use MediaWords::DBI::Stories::AP;

my $_test_feed;

sub _get_test_feed($)
{
    my ( $db ) = @_;

    if ( !$_test_feed )
    {
        my $test_medium = MediaWords::Test::DB::create_test_medium( $db, 'test' );
        $_test_feed = MediaWords::Test::DB::create_test_feed( $db, 'test', $test_medium );
    }

    return $_test_feed;

}

sub test_story($$$$)
{
    my ( $db, $content, $expected, $label ) = @_;

    my $test_feed = _get_test_feed( $db );

    my $story = MediaWords::Test::DB::create_test_story( $db, $label, $test_feed );

    $story->{ content } = $content;

    $story = MediaWords::Test::DB::add_content_to_test_story( $db, $story, $test_feed );

    my $got = MediaWords::DBI::Stories::AP::is_syndicated( $db, $story );

    is( $got, $expected, "story is syndicated: $label" );
}

sub get_ap_sentences()
{
    return [
        'AP sentence < 32.',
        'AP sentence >= 32 #1 (with some more text to pad out the length to 32).',
        'AP sentence >= 32 #2 (with some more text to pad out the length to 32).',
        'AP sentence >= 32 #3 (with some more text to pad out the length to 32).',
        'AP sentence >= 32 #4 (with some more text to pad out the length to 32).',
        'AP sentence >= 32 #5 (with some more text to pad out the length to 32).',
        'AP sentence >= 32 #6 (with some more text to pad out the length to 32).',
        'AP sentence >= 32 #7 (with some more text to pad out the length to 32).',
        'AP sentence >= 32 #8 (with some more text to pad out the length to 32).',
        'AP sentence >= 32 #9 (with some more text to pad out the length to 32).',
        'AP sentence >= 32 #10 (with some more text to pad out the length to 32).',
        'AP sentence >= 32 #11 (with some more text to pad out the length to 32).',
        'AP sentence >= 32 #12 (with some more text to pad out the length to 32).',
        'AP sentence >= 32 #13 (with some more text to pad out the length to 32).',
        'AP sentence >= 32 #14 (with some more text to pad out the length to 32).',
    ];
}

# add ap medium and some content so that we can find dup sentences
sub add_ap_content($)
{
    my ( $db ) = @_;

    my $ap_medium = MediaWords::Test::DB::create_test_medium( $db, MediaWords::DBI::Stories::AP::get_ap_medium_name() );

    my $feed = MediaWords::Test::DB::create_test_feed( $db, 'feed', $ap_medium );

    my $story = MediaWords::Test::DB::create_test_story( $db, 'story', $feed );

    $story->{ content } = join( "\n", @{ get_ap_sentences() } );

    $story = MediaWords::Test::DB::add_content_to_test_story( $db, $story, $feed );
}

sub test_ap_calls($)
{
    my ( $db ) = @_;

    add_ap_content( $db );

    my $ap_sentences                  = get_ap_sentences();
    my $ap_content_single_16_sentence = [ grep { length( $_ ) < 32 } @{ $ap_sentences } ]->[ 0 ];
    my $ap_content_32_sentences       = [ grep { length( $_ ) > 32 } @{ $ap_sentences } ];
    my $ap_content_single_32_sentence = $ap_content_32_sentences->[ 0 ];

    test_story( $db, 'foo', 0, "simple unsyndicated story" );

    test_story( $db, '(ap)', 1, "simple (ap) pattern" );

    test_story( $db, "associated press", 0, "only associated press" );

    test_story( $db, "'associated press'", 1, "quoted associated press" );

    test_story( $db, <<STORY, 1, "associated press and ap sentence" );
associated press.
$ap_content_single_32_sentence
STORY

    test_story( $db, <<STORY, 0, "associated press and short ap sentence" );
associated press.
$ap_content_single_16_sentence
STORY

    test_story( $db, $ap_content_single_32_sentence, 0, 'single ap sentence' );

    test_story( $db, <<STORY, 1, 'ap sentence and ap location' );
Boston (AP)
$ap_content_single_32_sentence
STORY

    test_story( $db, join( ' ', @{ $ap_sentences } ), 1, 'all ap sentences' );

    my $no_db_story = { content => 'foo' };
    is( MediaWords::DBI::Stories::AP::is_syndicated( $db, $no_db_story ), 0, 'no db story: simple story' );

    my $no_db_ap_story = { content => '(ap)' };
    is( MediaWords::DBI::Stories::AP::is_syndicated( $db, $no_db_ap_story ), 1, 'no db story: (ap) story' );

    my $no_db_ap_sentences_story = { content => join( ' ', @{ $ap_sentences } ) };
    is( MediaWords::DBI::Stories::AP::is_syndicated( $db, $no_db_ap_sentences_story ), 1, 'no db story: ap sentences' );
}

sub main()
{
    MediaWords::Test::DB::test_on_test_database( \&test_ap_calls );
}

main();
