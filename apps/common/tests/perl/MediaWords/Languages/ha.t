use strict;
use warnings;
use utf8;

use Test::More tests => 5;
use Test::NoWarnings;

use MediaWords::Languages::ha;

use Data::Dumper;
use Readonly;

sub test_stem($)
{
    my $lang = shift;

    # https://github.com/mediacloud/hausastemmer/blob/develop/tests/ref_stems/with_dict_lookup.py
    my $tokens_and_stems = {

        'ababen'  => 'ababe',
        'abin'    => 'abin',
        'abincin' => 'abinci',

        # Empty tokens
        '' => '',
    };

    for my $token ( keys %{ $tokens_and_stems } )
    {
        my $expected_stem = $tokens_and_stems->{ $token };
        my $actual_stem = $lang->stem_words( [ $token ] )->[ 0 ];
        is( $actual_stem, $expected_stem, "stem_words(): $token" );
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
