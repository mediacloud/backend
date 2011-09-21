use strict;
use warnings;
use Test::More tests => 6;
use MediaWords::Util::HTML;
use Lingua::EN::Sentence::MediaWords;
use Test::More;
use Test::Differences;
use Test::Deep;
use Perl6::Say;
use Data::Dumper;

BEGIN
{
    use_ok( 'MediaWords::DBI::DownloadTexts' );
}

require_ok( 'MediaWords::DBI::DownloadTexts' );


is( MediaWords::DBI::DownloadTexts::_new_lines_around_block_level_tags("<p>foo</p>"), 
     "\n\n<p>foo</p>\n\n" );

is( MediaWords::DBI::DownloadTexts::_new_lines_around_block_level_tags("<h1>HEADERING</h1><p>foo</p>"), 
    "\n\n<h1>HEADERING</h1>\n\n\n\n<p>foo</p>\n\n" );

is( MediaWords::DBI::DownloadTexts::_new_lines_around_block_level_tags("<p>foo<div>Bar</div></p>"), 
    "\n\n<p>foo\n\n<div>Bar</div>\n\n</p>\n\n");

my $test_text = "<h1>Title</h1>\n<p>1st sentence. 2nd sentence.</p>";

#say Dumper ( MediaWords::DBI::DownloadTexts::_new_lines_around_block_level_tags($test_text) );

my $sentences = Lingua::EN::Sentence::MediaWords::get_sentences( html_strip( MediaWords::DBI::DownloadTexts::_new_lines_around_block_level_tags($test_text) ) );

#say Dumper( $sentences );

cmp_deeply( $sentences, [ 'Title', '1st sentence.', '2nd sentence.' ] );