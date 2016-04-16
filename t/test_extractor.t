#
# Basic sanity test of extractor functionality
#
# Start ./python_scripts/extractor_python_readability_server.py and set
# MC_TEST_EXTRACTOR_PYTHONREADABILITY environment variable to to test Python
# Readability extractor
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Test::More;
use Test::NoWarnings;

use MediaWords::DBI::Stories;
use MediaWords::Test::Data;
use MediaWords::Test::Text;
use MediaWords::Util::Text;

use Data::Dumper;
use Readonly;
use File::Slurp;

sub extract_and_compare($$$$)
{
    my ( $test_dataset, $file, $title, $extractor_method ) = @_;

    my $test_stories =
      MediaWords::Test::Data::stories_arrayref_from_hashref(
        MediaWords::Test::Data::fetch_test_data_from_individual_files( "crawler_stories/$test_dataset/$extractor_method" ) );

    my $test_story_hash;
    map { $test_story_hash->{ $_->{ title } } = $_ } @{ $test_stories };

    my $story = $test_story_hash->{ $title };

    die "story '$title' not found " unless $story;

    my $data_files_path = MediaWords::Test::Data::get_path_to_data_files( 'crawler/' . $test_dataset );
    my $path            = $data_files_path . '/' . $file;

    my $content = MediaWords::Util::Text::decode_from_utf8( read_file( $path ) );

    my $results = MediaWords::DBI::Downloads::extract_content_ref( \$content, $extractor_method );

    # crawler test squeezes in story title and description into the expected output
    my @download_texts = ( $results->{ extracted_text } );
    my $combined_text  = MediaWords::DBI::Stories::combine_story_title_description_text(
        $story->{ title },
        $story->{ description },
        \@download_texts
    );

    my $expected_text = $story->{ extracted_text };
    my $actual_text   = $combined_text;

    MediaWords::Test::Text::eq_or_word_diff( $actual_text, $expected_text, "Extracted text comparison for $title" );
}

sub main
{
    # Errors might want to print out UTF-8 characters
    binmode( STDERR, ':utf8' );
    binmode( STDOUT, ':utf8' );
    my $builder = Test::More->builder;

    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    my @extractor_methods_to_test = ( 'InlinePythonReadability' );
    my $tests_planned             = 3;
    if ( defined $ENV{ MC_TEST_EXTRACTOR_PYTHONREADABILITY } )
    {
        push( @extractor_methods_to_test, 'PythonReadability' );
        ++$tests_planned;
    }

    plan tests => $tests_planned;

    foreach my $extractor_method ( @extractor_methods_to_test )
    {
        say STDERR "Testing extractor '$extractor_method'...";
        extract_and_compare( 'gv', 'index.html.1', 'Brazil: Amplified conversations to fight the Digital Crimes Bill',
            $extractor_method );
    }

    Test::NoWarnings::had_no_warnings();
}

main();
