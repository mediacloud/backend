#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Test::More tests => 5;
use Test::Differences;
use Test::NoWarnings;

use MediaWords::Languages::ha;

use Data::Dumper;
use Readonly;

sub test_stem($)
{
    my $lang = shift;

    # https://github.com/berkmancenter/mediacloud-hausastemmer/blob/develop/tests/ref_stems/with_dict_lookup.py
    my $tokens_and_stems = {

        'ababen'  => 'ababe',
        'abin'    => 'abin',
        'abincin' => 'abinci',

        # Empty tokens
        '' => '',
    };

    for my $token ( keys %{ $tokens_and_stems } )
    {
        my $expected_stem  = $tokens_and_stems->{ $token };
        my @tokens_to_stem = ( $token );
        my $actual_stem    = $lang->stem( @tokens_to_stem )->[ 0 ];
        is( $actual_stem, $expected_stem, "stem(): $token" );
    }
}

sub main()
{
    # Test::More UTF-8 output
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    my $lang = MediaWords::Languages::ha->new();

    test_stem( $lang );
}

main();
