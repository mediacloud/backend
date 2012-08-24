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

use MediaWords::Languages::en_US;
use Data::Dumper;

my $test_string = <<'QUOTE';
Sentence contain version 2.0 of the text. Foo.
QUOTE

my $lang = MediaWords::Languages::en_US->new();

my $expected_sentences = [ 'Sentence contain version 2.0 of the text.', "Foo." ];

{
    is(
        join( '||', @{ Lingua::EN::Sentence::MediaWords::get_sentences( $test_string ) } ),
        join( '||', @{ $expected_sentences } ),
        "sentence_split"
    );
}
