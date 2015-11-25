package MediaWords::Languages::fi;
use Moose;
with 'MediaWords::Languages::Language';

#
# Finnish
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'fi';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'fi', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'fi', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'fi', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'fi', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # An example of an actually long word that has been used in the Finnish language is
    # kolmivaihekilowattituntimittari which means "three phase kilowatt hour meter"
    # (31 letters) or lentokonesuihkuturbiinimoottoriapumekaanikkoaliupseerioppilas
    # "airplane jet turbine engine auxiliary mechanic under officer student" (61 letters)
    # which has been deprecated. If conjugation is allowed even longer real words can be
    # made. Allowing derivatives and clitic allows the already lengthy word to grow even
    # longer even though the real usability of the word starts to degrade. The Finnish
    # language uses free forming of composite words: New words can even be formed during
    # a conversation. This allows for adding nouns after each other without breaking
    # grammar rules.
    return 61;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'fi',
        'lib/MediaWords/Languages/resources/fi_nonbreaking_prefixes.txt', $story_text );
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
