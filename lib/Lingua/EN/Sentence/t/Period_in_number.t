#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::More tests => 1;
use utf8;

use Lingua::Stem;
use Lingua::Stem::Ru;
use Data::Dumper;
use Perl6::Say;
use Lingua::EN::Sentence::MediaWords;
use Lingua::Stem::Snowball;
use MediaWords::Util::Stemmer;

my $test_string = <<'QUOTE';
Sentence contain version 2.0 of the text. Foo.
QUOTE

my $expected_sentences =
[
 'Sentence contain version 2.0 of the text.',
 "Foo."
];

{
    is( join ( '||', @{Lingua::EN::Sentence::MediaWords::get_sentences($test_string)}), join ('||', @{ $expected_sentences} ), "sentence_split" );

}
