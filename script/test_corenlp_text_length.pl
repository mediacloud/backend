#!/usr/bin/env perl
#
# Post texts of varying length to CoreNLP annotator, see how long it takes to
# process each one
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::CoreNLP;
use MediaWords::Util::Timing;

use Readonly;

sub _generate_text_of_length($$)
{
    my ( $template_text, $length ) = @_;

    my $text = '';
    while ( length( $text ) < $length )
    {
        $text .= $template_text . ' ';
    }
    $text = substr( $text, 0, $length );
    return $text;
}

sub main
{
    local $| = 1;

    # Readonly my $sentence => 'Buffalo buffalo Buffalo buffalo buffalo buffalo Buffalo buffalo.';
    Readonly my $sentence => 'The quick brown fox jumps over the lazy dog.';

    Readonly my $increment_length => 1024 * 10;
    Readonly my $increment_count  => 1000;

    for ( my $x = 1 ; $x <= $increment_count ; ++$x )
    {
        my $text_length = $x * $increment_length;
        my $text = _generate_text_of_length( $sentence, $text_length );

        my $start_time = start_time( 'corenlp-text-length' );
        my $results    = MediaWords::Util::CoreNLP::_annotate_text( $text );
        my $duration   = stop_time( 'corenlp-text-length', $start_time );

        printf STDOUT "%d\t%.2f\n", $text_length, $duration;
    }
}

main();
