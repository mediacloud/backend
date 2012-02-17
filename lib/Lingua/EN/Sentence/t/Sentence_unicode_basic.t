#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::NoWarnings;
use Test::More tests => 1 + 1;
use utf8;

use Lingua::Stem;
use Lingua::Stem::Ru;
use Data::Dumper;
use Perl6::Say;
use Lingua::EN::Sentence::MediaWords;
use Lingua::Stem::Snowball;
use MediaWords::Util::Stemmer;

my $test_string = <<'QUOTE';
Non Mega Não.
QUOTE

my $expected_sentences =
[
'Non Mega Não.',
];

{
    is( join ( '||', @{Lingua::EN::Sentence::MediaWords::get_sentences($test_string)}), join ('||', @{ $expected_sentences} ), "sentence_split" );

}
