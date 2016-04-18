package MediaWords::Test::Text;

=head1 NAME

MediaWords::Test::Text - helper functions for testing text

=cut

use strict;
use warnings;

use Test::More;
use Text::WordDiff;

=head1 FUNCTIONS

=head2 eq_or_word_diff( $got, $expected, $message )

Fails test if $got and $expected are not equal strings.  In the case, prints a word by word diff that in most cases
is much more useful than the line by line diff of Test::Text::eq_or_diff.

=cut

sub eq_or_word_diff($$$)
{
    my ( $actual_text, $expected_text, $message ) = @_;

    if ( ( !defined $actual_text ) and ( !defined $expected_text ) )
    {
        ok( 1, $message );
        return;
    }

    # word_diff always returns output, even if the strings are equal, so only do the diff if the strings are different
    if ( $actual_text eq $expected_text )
    {
        ok( 1, $message );
        return;
    }

    my $diff = Text::WordDiff::word_diff( \$actual_text, \$expected_text );

    ok( 0, "$message:\n(got: RED expected: GREEN)\n $diff" );

}

1;
