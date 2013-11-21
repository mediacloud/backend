package MediaWords::Languages::lt;
use Moose;
with 'MediaWords::Languages::Language';

#
# Lithuanian
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Lingua::Stem::Snowball::Lt;

# Lingua::Stem::Snowball::Lt instance (if needed), lazy-initialized in stem()
has 'lt_stemmer' => ( is => 'rw', default => 0 );

sub get_language_code
{
    return 'lt';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/lt_stoplist.txt' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/lt_stoplist.txt' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/lt_stoplist.txt' );
}

sub stem
{
    my $self = shift;

    # (Re-)initialize stemmer if needed
    if ( $self->lt_stemmer == 0 )
    {
        $self->lt_stemmer( Lingua::Stem::Snowball::Lt->new() );
    }

    my @stems = $self->lt_stemmer->stem( \@_ );

    return \@stems;
}

sub get_word_length_limit
{
    my $self = shift;

    # The two longest Lithuanian words are 37 letters long: 1) the adjective
    # septyniasdešimtseptyniastraipsniuose – the plural locative case of the
    # adjective septyniasdešimtseptyniastraipsnis, meaning "(object) with
    # seventy-seven articles"; 2) the participle
    # nebeprisikiškiakopūsteliaudavusiuose, "in those that were repeatedly
    # unable to pick enough of small wood-sorrels in the past" – the plural
    # locative case of past iterative active participle of verb
    # kiškiakopūsteliauti meaning "to pick wood-sorrels" (edible forest plant
    # with sour taste, word by word translation "rabbit cabbage"). The word
    # is commonly attributed to famous Lithuanian language teacher Jonas
    # Kvederaitis, who actually used the plural first person of past iterative
    # tense, nebeprisikiškiakopūstaudavome.[citation needed]
    return 37;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'lt',
        'lib/MediaWords/Languages/resources/lt_nonbreaking_prefixes.txt', $story_text );
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
        'naujienų', 'BNS',       'skelbti',      'cituoti',        'atgaminti',   'kopijuoti',
        'dauginti',  'platinti',  'informavimo',  'raštiško',     'raštišką', 'sutikimo',
        'sutikimą', 'sutikimas', 'neleidžiama', 'draudžiama',    'taisyklės',  'teisės',
        'saugomos',  'griežtai', 'DELFI',        'žiniasklaidos', 'nurodyti',    'šaltinį',
        'šaltinis'
    );
    return \@noise_strings;
}

sub get_copyright_strings
{
    my $self = shift;
    my @copyright_strings =
      ( 'copyright', 'copying', '&copy;', 'all rights reserved', 'teisės saugomos', 'visos teisės saugomos', );
    return \@copyright_strings;
}

sub get_locale_codes_api_object
{
    my $self = shift;
    return $self->_get_locale_country_multilingual_object( 'lt' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'antigva ir barbuda'                               => 'antigva',            # 'antigua and barbuda'
        'bosnija ir hercegovina'                           => 'bosnija',            # 'bosnia and herzegovina'
        'centrinės afrikos respublika'                    => 'centrinė afrika',   # 'central african republic'
        'didžiosios britanijos mergelių salos'           => -1,                   # 'virgin islands, british'
        'dramblio kaulo krantas'                           => -1,                   # 'cote d\'ivoire'
        'heardo ir mcdonaldo salų sritis'                 => -1,                   # 'heard island and mcdonald islands'
        'indijos vandenyno britų sritis'                  => -1,                   # 'british indian ocean territory'
        'jungtiniai arabų emyratai'                       => 'arabų emyratai',    # 'united arab emirates'
        'jungtinių valstijų mažosios aplinkinės salos' => -1,                   # 'united states minor outlying islands'
        'kinijos s.a.r.honkongas'                          => 'honkongas',          # 'hong kong'
        'kongo demokratinė respublika'                    => 'kongas-kinšasa',    # 'congo, the democratic republic of the'
        'marianos šiaurinės salos'                       => -1,                   # 'northern mariana islands'
        'mergelių salos (jav)'                            => -1,                   # 'virgin islands, u.s.'
        'papua naujoji gvinėja'                           => 'papua gvinėja',     # 'papua new guinea'
        'prancūzijos pietų sritys'                       => -1,                   # 'french southern territories'
        'rytų džordžija ir rytų sandwich salos' => -1,              # 'south georgia and the south sandwich islands'
        'san tomė ir principė'                    => -1,              # 'sao tome and principe'
        'sen pjeras ir mikelonas'                   => -1,              # 'saint pierre and miquelon'
        'sent kitsas ir nevis'                      => -1,              # 'saint kitts and nevis'
        'svalbardo ir jan majen salos'              => -1,              # 'svalbard and jan mayen'
        'trinidadas ir tobagas'                     => 'trinidadas',    # 'trinidad and tobago'
        'turkso ir caicoso salos'                   => -1,              # 'turks and caicos islands'
        'wallisas ir futuna'                        => 'futuna',        # 'wallis and futuna'
        'šventasis vincentas ir grenadinai'        => -1,              # 'saint vincent and the grenadines'
    };

}

1;
