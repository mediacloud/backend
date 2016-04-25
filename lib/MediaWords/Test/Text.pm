package MediaWords::Test::Text;

=head1 NAME

MediaWords::Test::Text - helper functions for testing text

=cut

use strict;
use warnings;

use Test::More;
use Text::WordDiff;

=head1 FUNCTIONS

=head2 eq_or_sentence_diff( $got, $expected, $message )

Fails test if $got and $expected are not equal strings.  In the case, prints a
sentence by sentence diff that in most cases is much more useful than the line
by line diff of Test::Text::eq_or_diff.

If $verbatim is true, strings are compared verbatim. By default, whitespace is
normalized before comparing texts.

=cut

sub eq_or_sentence_diff($$$;$)
{
    my ( $actual_text, $expected_text, $message, $verbatim ) = @_;

    if ( ( !defined $actual_text ) and ( !defined $expected_text ) )
    {
        ok( 1, $message );
        return;
    }

    if ( $actual_text eq $expected_text )
    {
        ok( 1, $message );
        return;
    }

    unless ( $verbatim )
    {
        $actual_text =~ s/\R/\n/g;
        $expected_text =~ s/\R/\n/g;

        $actual_text =~ s/\s+/ /g;
        $expected_text =~ s/\s+/ /g;

        $actual_text =~ s/^\s+|\s+$//g;
        $expected_text =~ s/^\s+|\s+$//g;
    }

    say STDERR 'Actual text: ' . $actual_text;
    say STDERR 'Expected text: ' . $expected_text;

    my $worddiff_style = 'ANSIColor';
    my $expected_mark  = 'GREEN';
    my $got_mark       = 'RED';
    if ( ( $ENV{ DEBIAN_FRONTEND } // '' ) eq 'noninteractive' )
    {
        # No color in CI server logs
        $worddiff_style = 'HTML';
        $expected_mark  = '<ins>';
        $got_mark       = '<del>';
    }

    my $diff = Text::WordDiff::word_diff( \$actual_text, \$expected_text, { STYLE => $worddiff_style } );

    ok( 0, "$message:\n(got: $got_mark; expected: $expected_mark)\n $diff" );

}

1;
