use strict;
use warnings;
use Data::Dumper;

# basic sanity test of crawler functionality

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

require Test::NoWarnings;

use Test::More skip_all => "need to figure out why tests haven't worked";
use Test::Differences;
use Test::Deep;

use MediaWords::Crawler::Engine;
use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::MediaSets;
use MediaWords::DBI::Stories;
use MediaWords::Test::DB;
use MediaWords::Test::Data;
use DBIx::Simple::MediaWords;
use MediaWords::StoryVectors;
use LWP::UserAgent;

use Data::Sorting qw( :basics :arrays :extras );
use Readonly;
use Encode;

sub extract_and_compare
{
    my ( $file, $title ) = @_;

    my $test_stories =
      MediaWords::Test::Data::stories_arrayref_from_hashref(
        MediaWords::Test::Data::fetch_test_data_from_individual_files( 'crawler_stories' ) );

    my $test_story_hash;
    map { $test_story_hash->{ $_->{ title } } = $_ } @{ $test_stories };

    my $story = $test_story_hash->{ $title };

    die "story '$title' not found " unless $story;

    my $path = "$FindBin::Bin/data/crawler/gv/$file";

    if ( !open( FILE, $path ) )
    {
        return undef;
    }

    my $content;

    while ( my $line = <FILE> )
    {
        $content .= decode( 'utf-8', $line );
    }

    my $results =
      MediaWords::DBI::Downloads::_do_extraction_from_content_ref( \$content, $story->{ title }, $story->{ description } );

    #   my $results = MediaWords::DBI::Downloads::_do_extraction_from_content_ref( \$content, $title, '');

    MediaWords::DBI::DownloadTexts::update_extractor_results_with_text_and_html( $results );

    is(
        substr( $results->{ extracted_text }, 0, 100 ),
        substr( $story->{ extracted_text },   0, 100 ),
        "Extracted text comparison for $title"
    );

    #say Dumper ( $results );

    #exit;
}

sub main
{

    my $dump = @ARGV;
    extract_and_compare( 'index.html.1', 'Brazil: Amplified conversations to fight the Digital Crimes Bill' );

    Test::NoWarnings::had_no_warnings();

}

main();

