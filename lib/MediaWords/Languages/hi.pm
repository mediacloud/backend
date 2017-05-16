package MediaWords::Languages::hi;

#
# Hindi
#

use strict;
use warnings;
use utf8;

use Moose;
with 'MediaWords::Languages::Language';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Encode;
use Readonly;
use Text::Hunspell;

sub BUILD
{
    my ( $self, $args ) = @_;

    my $hunspell = Text::Hunspell->new(
        'lib/MediaWords/Languages/resources/hi/hindi-hunspell/dict-hi_IN/hi_IN.aff',    # Hunspell affix file
        'lib/MediaWords/Languages/resources/hi/hindi-hunspell/dict-hi_IN/hi_IN.dic'     # Hunspell dictionary file
    );

    # Quick self-test to make sure that Hunspell is installed and dictionary
    # is available (because otherwise Text::Hunspell fails silently)
    my @self_test_encoded_stems = $hunspell->stem( 'गुरुओं' );
    if ( ( !$self_test_encoded_stems[ 0 ] ) or decode( 'utf-8', $self_test_encoded_stems[ 0 ] ) ne 'गुरु' )
    {
        die <<EOF;
Hunspell self-test failed; make sure that Hunspell is installed and
dictionaries are accessible, e.g. you might need to fetch Git submodules by
running:

    git submodule update --init --recursive

EOF
    }

    $self->{ _hunspell_hindi } = $hunspell;
}

sub get_language_code
{
    return 'hi';
}

sub fetch_and_return_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/hi_stopwords.txt' );
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
            my @encoded_stems = $self->{ _hunspell_hindi }->stem( $token );
            TRACE "Encoded stems for '$token': " . Dumper( \@encoded_stems );

            if ( scalar @encoded_stems )
            {
                my $encoded_stem = $encoded_stems[ 0 ];

                eval { $stem = decode( 'utf-8', $encoded_stem ); };
                if ( $@ )
                {
                    TRACE "Unable to decode stem '$encoded_stem' for token '$token': $@_";
                    $stem = $token;
                }

                unless ( $stem )
                {
                    TRACE "Unable to stem for token '$token'";
                    $stem = $token;
                }

            }
            else
            {
                TRACE "Token '$token' was not found.";
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

    # Replace Hindi's "।" with line break to make Lingua::Sentence split on both "।" and period
    $story_text =~ s/।/।\n\n/gs;

    # No non-breaking prefixes in Hindi, so using English file
    Readonly my $nonbreaking_prefix_file => 'lib/MediaWords/Languages/resources/en_nonbreaking_prefixes.txt';
    return $self->_tokenize_text_with_lingua_sentence( 'en', $nonbreaking_prefix_file, $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
