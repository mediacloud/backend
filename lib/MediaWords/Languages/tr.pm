package MediaWords::Languages::tr;
use Moose;
with 'MediaWords::Languages::Language';

#
# Turkish
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'tr';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/tr_stoplist.txt' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/tr_stoplist.txt' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/tr_stoplist.txt' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'tr', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # Muvaffakiyetsizleştiricileştiriveremeyebileceklerimizdenmişsinizcesine, at 70 letters, has been
    # cited as the longest Turkish word, though it is a compound word and Turkish, as an agglutinative
    # language, carries the potential for words of theoretically infinite length.[citation needed]
    return 70;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'tr',
        'lib/MediaWords/Languages/resources/tr_nonbreaking_prefixes.txt', $story_text );
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
