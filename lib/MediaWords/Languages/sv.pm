package MediaWords::Languages::sv;
use Moose;
with 'MediaWords::Languages::Language';

#
# Swedish
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'sv';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'sv', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'sv', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'sv', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'sv', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

# The longest word in the Swedish language, according to Guinness World Records, is
# Nordöstersjökustartilleriflygspaningssimulatoranläggningsmaterielunderhållsuppföljningssystemdiskussionsinläggsförberedelsearbeten
# (130 letters). It means "Northern Baltic Sea Coast Artillery Reconnaissance Flight
# Simulator Facility Equipment Maintenance Follow-Up System Discussion Post Preparation
# Work(s)." Since compound words are written together to form entirely new words, the
# "longest one" could be arbitrarily long.
# (http://en.wikipedia.org/wiki/Longest_words#Swedish)
    return 130;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'sv',
        'lib/MediaWords/Languages/resources/sv_nonbreaking_prefixes.txt', $story_text );
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
