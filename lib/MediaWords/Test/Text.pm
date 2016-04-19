package MediaWords::Test::Text;

=head1 NAME

MediaWords::Test::Text - helper functions for testing text

=cut

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Test::More;
use MediaWords::Languages::en;

=head1 FUNCTIONS

=head2 eq_or_sentence_diff( $got, $expected, $message )

Fails test if $got and $expected are not equal strings.  In the case, prints a
sentence by sentence diff that in most cases is much more useful than the line
by line diff of Test::Text::eq_or_diff.

=cut

sub eq_or_sentence_diff($$$)
{
    my ( $actual_text, $expected_text, $message ) = @_;

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

    # Assume that unit tests will use either English or other language with
    # Latin alphabet (for which ::en is close enough)
    my $en = MediaWords::Languages::en->new();

    my $actual_sentences   = $en->get_sentences( $actual_text );
    my $expected_sentences = $en->get_sentences( $expected_text );

    is_deeply( $actual_sentences, $expected_sentences, $message );
}

1;
