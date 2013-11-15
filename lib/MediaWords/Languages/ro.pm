package MediaWords::Languages::ro;
use Moose;
with 'MediaWords::Languages::Language';

#
# Romanian
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'ro';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/ro_stoplist.txt' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/ro_stoplist.txt' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/ro_stoplist.txt' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'ro', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # The 44-letter word pneumonoultramicroscopicsilicovolcaniconioză is the longest word.
    # It is a substantive referring to a disease.
    return 44;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'ro',
        'lib/MediaWords/Languages/resources/ro_nonbreaking_prefixes.txt', $story_text );
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

sub get_locale_codes_api_object
{
    my $self = shift;
    return $self->_get_locale_country_multilingual_object( 'ro' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'africa de sud'                                => 'africa sud',      # 'south africa'
        'antigua și barbuda'                          => 'antigua',         # 'antigua and barbuda'
        'bosnia și herțegovina'                      => 'bosnia',          # 'bosnia and herzegovina'
        'coasta de fildeș'                            => 'coasta fildeș',  # 'cote d\'ivoire'
        'coreea de nord'                               => 'coreea nord',     # 'korea, democratic people\'s republic of'
        'coreea de sud'                                => 'coreea sud',      # 'korea, republic of'
        'emiratele arabe unite'                        => 'emiratele arabe', # 'united arab emirates'
        'insula heard și insulele mcdonald'           => -1,                # 'heard island and mcdonald islands'
        'insulele georgia de sud și sandwich de sud'  => -1,                # 'south georgia and the south sandwich islands'
        'insulele mariane de nord'                     => -1,                # 'northern mariana islands'
        'insulele turks și caicos'                    => -1,                # 'turks and caicos islands'
        'insulele virgine britanice'                   => -1,                # 'virgin islands, british'
        'insulele virgine s.u.a.'                      => -1,                # 'virgin islands, u.s.'
        'papua noua guinee'                            => 'papua guinee',    # 'papua new guinea'
        'r.a.s. hong kong a chinei'                    => 'hong kong',       # 'hong kong'
        'r.a.s. macao a chinei'                        => 'macao',           # 'macao'
        'republica democrată congo'                   => 'congo-kinshasa',  # 'congo, the democratic republic of the'
        'sahara de vest'                               => 'sahara vest',     # 'western sahara'
        'saint kitts și nevis'                        => -1,                # 'saint kitts and nevis'
        'saint pierre și miquelon'                    => -1,                # 'saint pierre and miquelon'
        'saint vincent și grenadines'                 => -1,                # 'saint vincent and the grenadines'
        'sao tome și principe'                        => -1,                # 'sao tome and principe'
        'svalbard și jan mayen'                       => -1,                # 'svalbard and jan mayen'
        'teritoriile australe și antarctice franceze' => -1,                # 'french southern territories'
        'teritoriile îndepărtate ale statelor unite' => -1,                # 'united states minor outlying islands'
        'teritoriul britanic din oceanul indian'       => -1,                # 'british indian ocean territory'
        'timorul de est'                               => 'timorul est',     # 'timor-leste'
        'wallis și futuna'                            => 'futuna',          # 'wallis and futuna'
    };

}

1;
