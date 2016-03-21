package MediaWords::Languages::no;
use Moose;
with 'MediaWords::Languages::Language';

#
# Norwegian (Bokmål)
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'no';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'no', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'no', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'no', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'no', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # The longest word in Norwegian, that is a real word in ordinary use, is
    # menneskerettighetsorganisasjonene (33 letters).[citation needed] The
    # meaning is "the human rights organizations". Being used mostly in
    # statistics, the term sannsynlighetstetthetsfunksjonene (meaning “the
    # probability density functions”) is also 33 characters long. The physics
    # term minoritetsladningsbærerdiffusjonskoeffisientmålingsapparatur has
    # 60 characters, but is not a common word. Its meaning is "(a) device
    # for measuring the distance between particles in a crystal".
    return 60;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'no',
        'lib/MediaWords/Languages/resources/no_nonbreaking_prefixes.txt', $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

sub get_noise_strings
{
    my $self          = shift;
    my @noise_strings = (

        # FIXME add language-dependent noise strings (see en.pm for example)
    );
    return \@noise_strings;
}

sub get_copyright_strings
{
    my $self              = shift;
    my @copyright_strings = (

        # FIXME add language-dependent copyright strings (see en.pm for example)
        'copyright',
        'copying',
        '&copy;',
        'all rights reserved',
    );
    return \@copyright_strings;
}

1;
