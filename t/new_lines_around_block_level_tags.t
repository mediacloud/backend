use strict;
use warnings;

use Test::NoWarnings;
use Test::More tests => 13 + 1;
use MediaWords::Util::HTML;
use MediaWords::Languages::en;
use Test::More;
use Test::Differences;
use Test::Deep;

use Data::Dumper;

BEGIN
{
    use_ok( 'MediaWords::Util::HTML' );
}

require_ok( 'MediaWords::Util::HTML' );

ok( !MediaWords::Util::HTML::contains_block_level_tags( '<b> ' ), 'contains_block_level_tags' );

is( MediaWords::Util::HTML::new_lines_around_block_level_tags( "<p>foo</p>" ), "\n\n<p>foo</p>\n\n" );

is( MediaWords::Util::HTML::new_lines_around_block_level_tags( "<h1>HEADERING</h1><p>foo</p>" ),
    "\n\n<h1>HEADERING</h1>\n\n\n\n<p>foo</p>\n\n" );

is( MediaWords::Util::HTML::new_lines_around_block_level_tags( "<p>foo<div>Bar</div></p>" ),
    "\n\n<p>foo\n\n<div>Bar</div>\n\n</p>\n\n" );

my $test_text = "<h1>Title</h1>\n<p>1st sentence. 2nd sentence.</p>";

#say Dumper ( MediaWords::Util::HTML::new_lines_around_block_level_tags($test_text) );

my $lang = MediaWords::Languages::en->new();
my $sentences =
  $lang->get_sentences( html_strip( MediaWords::Util::HTML::new_lines_around_block_level_tags( $test_text ) ) );

#say Dumper( $sentences );

cmp_deeply( $sentences, [ 'Title', '1st sentence.', '2nd sentence.' ] );

ok( MediaWords::Util::HTML::contains_block_level_tags( '<div class="translation"> ) ' ), 'contains_block_level_tags' );

ok( !MediaWords::Util::HTML::contains_block_level_tags( '<divXXXXXX> ) ' ), 'contains_block_level_tags' );

ok( MediaWords::Util::HTML::contains_block_level_tags( '<p> Foo ' ), 'contains_block_level_tags' );

ok( MediaWords::Util::HTML::contains_block_level_tags( '<P> Foo ' ), 'contains_block_level_tags' );

ok( MediaWords::Util::HTML::contains_block_level_tags( '<p> Foo </P> ' ), 'contains_block_level_tags' );

ok( MediaWords::Util::HTML::contains_block_level_tags( ' Foo </P> ' ), 'contains_block_level_tags' );
