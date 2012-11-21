#!/usr/bin/perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::NoWarnings;
use Test::More tests => 5 + 1;
use utf8;

# Test::More UTF-8 output
my $builder = Test::More->builder;
binmode $builder->output,         ":utf8";
binmode $builder->failure_output, ":utf8";
binmode $builder->todo_output,    ":utf8";

use MediaWords::Languages::en;
use Data::Dumper;

my $test_string;
my $expected_sentences;

my $lang = MediaWords::Languages::en->new();

#
# Period in number
#
$test_string = <<'QUOTE';
Sentence contain version 2.0 of the text. Foo.
QUOTE

$expected_sentences = [ 'Sentence contain version 2.0 of the text.', 'Foo.' ];

{
    is( join( '||', @{ $lang->get_sentences( $test_string ) } ), join( '||', @{ $expected_sentences } ), "sentence_split" );
}

#
# 'May' ending
#
$test_string = <<'QUOTE';
Sentence ends in May. This is the next sentence. Foo.
QUOTE

$expected_sentences = [ 'Sentence ends in May.', 'This is the next sentence.', 'Foo.' ];

{
    is( join( '||', @{ $lang->get_sentences( $test_string ) } ), join( '||', @{ $expected_sentences } ), "sentence_split" );
}

#
# Punctuation
#
$test_string = <<'QUOTE';
Leave the city! [Mega No!], l.
QUOTE

$expected_sentences = [ 'Leave the city!', '[Mega No!], l.' ];

{
    is( join( '||', @{ $lang->get_sentences( $test_string ) } ), join( '||', @{ $expected_sentences } ), "sentence_split" );
}

#
# Basic Unicode
#
$test_string = <<'QUOTE';
Non Mega Não.
QUOTE

$expected_sentences = [ 'Non Mega Não.' ];

{
    is( join( '||', @{ $lang->get_sentences( $test_string ) } ), join( '||', @{ $expected_sentences } ), "sentence_split" );
}

#
# Unicode
#
$test_string = <<'QUOTE';
Non Mega Não! [Mega No!], l.
QUOTE

$expected_sentences = [ 'Non Mega Não!', '[Mega No!], l.', ];

{
    is( join( '||', @{ $lang->get_sentences( $test_string ) } ), join( '||', @{ $expected_sentences } ), "sentence_split" );
}
