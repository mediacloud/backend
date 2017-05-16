package MediaWords::Languages::ha;

#
# Hausa
#

use strict;
use warnings;
use utf8;

use Moose;
with 'MediaWords::Languages::Language';

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

# Import py_hausa_stem()
import_python_module( __PACKAGE__, 'mediawords.languages.ha' );

use Readonly;

sub get_language_code
{
    return 'ha';
}

sub fetch_and_return_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/ha_stopwords.txt' );
}

sub stem
{
    my $self = shift;

    my @stems;
    for my $token ( @_ )
    {
        my $stem;

        unless ( $token )
        {
            TRACE 'Token is empty or undefined.';
            $stem = $token;
        }
        else
        {
            $stem = py_hausa_stem( $token );

            unless ( $stem )
            {
                TRACE "Unable to stem for token '$token'";
                $stem = $token;
            }
        }

        push( @stems, $stem );
    }

    return \@stems;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;

    # No non-breaking prefixes in Hausa, so using English file
    Readonly my $nonbreaking_prefix_file => 'lib/MediaWords/Languages/resources/en_nonbreaking_prefixes.txt';
    return $self->_tokenize_text_with_lingua_sentence( 'en', $nonbreaking_prefix_file, $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
