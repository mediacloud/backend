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

use Data::Dumper;
use MediaWords::Languages::en_US;

my $test_string = <<'QUOTE';
Non Mega Não.
QUOTE

my $lang = MediaWords::Languages::en_US->new();

my $expected_sentences = [ 'Non Mega Não.', ];

{
    is(
        join( '||', @{ Lingua::EN::Sentence::MediaWords::get_sentences( $test_string ) } ),
        join( '||', @{ $expected_sentences } ),
        "sentence_split"
    );
}
