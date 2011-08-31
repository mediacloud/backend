#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::More tests => 7;
use utf8;

use Lingua::Stem;
use Lingua::Stem::Ru;
use Data::Dumper;
use Perl6::Say;
use Lingua::EN::Sentence::MediaWords;
use Lingua::Stem::Snowball;
use MediaWords::Util::Stemmer;

my $test_string = <<'QUOTE';
Sentence ends in May. This is the next sentence. Foo.
QUOTE

my $expected_sentences =
[
 'Sentence ends in May.',
 "This is the next sentence.",
 "Foo."
];

{
    is( join ( '||', @{Lingua::EN::Sentence::MediaWords::get_sentences($test_string)}), join ('||', @{ $expected_sentences} ), "sentence_split" );

}
