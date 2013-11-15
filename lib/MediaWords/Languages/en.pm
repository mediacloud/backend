package MediaWords::Languages::en;
use Moose;
with 'MediaWords::Languages::Language';

#
# English
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'en';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'en', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/en_stoplist_short.txt' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/en_stoplist_long.txt' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'en', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # The 45-letter word pneumonoultramicroscopicsilicovolcanoconiosis is the longest English word
    # that appears in a major dictionary.[6] Originally coined to become a candidate for the longest
    # word in English, the term eventually developed some independent use in medicine.[7] It is
    # referred to as "P45" by researchers.[8]
    # (http://en.wikipedia.org/wiki/Longest_words#English)
    return 45;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'en',
        'lib/MediaWords/Languages/resources/en_nonbreaking_prefixes.txt', $story_text );
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
        'comment',      'advertise',        'advertisement',       'advertising',
        'classified',   'subscribe',        'subscription',        'please',
        'address',      'published',        'obituary',            'current',
        'high',         'low',              'click',               'filter',
        'select',       'copyright',        'reserved',            'abusive',
        'defamatory',   'post',             'trackback',           'url',
        'terms of use', 'data provided by', 'data is provided by', 'privacy policy',
    );
    return \@noise_strings;
}

sub get_copyright_strings
{
    my $self = shift;
    my @copyright_strings = ( 'copyright', 'copying', '&copy;', 'all rights reserved', );
    return \@copyright_strings;
}

sub get_locale_codes_api_object
{
    my $self = shift;
    return $self->_get_locale_country_multilingual_object( 'en' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {

        # 'afghanistan',
        # 'aland islands',
        # 'albania',
        # 'algeria',
        'american samoa' => -1,

        # 'andorra',
        # 'angola',
        # 'anguilla',
        # 'antarctica',
        'antigua and barbuda' => 'antigua',

        # 'argentina',
        # 'armenia',
        # 'aruba',
        # 'australia',
        # 'austria',
        # 'azerbaijan',
        # 'bahamas',
        # 'bahrain',
        # 'bangladesh',
        # 'barbados',
        # 'belarus',
        # 'belgium',
        # 'belize',
        # 'benin',
        # 'bermuda',
        # 'bhutan',
        'bolivia, plurinational state of'   => 'bolivia',
        'bonaire, saint eustatius and saba' => -1,
        'bosnia and herzegovina'            => 'bosnia',

        # 'botswana',
        # 'bouvet island',
        # 'brazil',
        'british indian ocean territory' => -1,
        'brunei darussalam'              => 'brunei',

        # 'bulgaria',
        # 'burkina faso',
        # 'burundi',
        # 'cambodia',
        # 'cameroon',
        # 'canada',
        'cape verde' => -1,

        # 'cayman islands',
        'central african republic' => 'central african',

        # 'chad',
        # 'chile',
        # 'china',
        'christmas island'        => -1,
        'cocos (keeling) islands' => -1,

        # 'colombia',
        # 'comoros',
        # 'congo',
        'congo, the democratic republic of the' => 'congo-kinshasa',

        'cook islands' => -1,

        # 'costa rica',
        # 'cote d\'ivoire',
        # 'croatia',
        # 'curacao',
        # 'cuba',
        # 'cyprus',
        # 'czech republic',
        # 'denmark',
        # 'djibouti',
        'dominica'           => -1,
        'dominican republic' => 'dominican',

        # 'ecuador',
        # 'egypt',
        'el salvador' => 'salvador el',

        # 'equatorial guinea',
        # 'eritrea',
        # 'estonia',
        # 'ethiopia',
        'falkland islands (malvinas)' => 'falkland',

        'faroe islands' => 'faroe',

        # 'fiji',
        # 'finland',
        # 'france',
        'france, metropolitan' => -1,

        'french guiana'               => 'guiana french',
        'french polynesia'            => 'polynesia french',
        'french southern territories' => -1,

        # 'gabon',
        # 'gambia',
        # 'georgia',
        # 'germany',
        # 'ghana',
        # 'gibraltar',
        # 'greece',
        # 'greenland',
        # 'grenada',
        # 'guadeloupe',
        # 'guam',
        # 'guatemala',
        # 'guernsey',
        # 'guinea',
        # 'guinea-bissau',
        # 'guyana',
        # 'haiti',
        'heard island and mcdonald islands' => -1,
        'holy see (vatican city state)'     => 'vatican',

        # 'honduras',
        # 'hong kong',
        # 'hungary',
        # 'iceland',
        # 'india',
        # 'indonesia',
        'iran, islamic republic of' => 'iran',

        # 'iraq',
        # 'ireland',
        'isle of man' => -1,

        # 'israel',
        # 'italy',
        # 'jamaica',
        # 'japan',
        'jersey'                                  => -1,              #the island of Jersy would be confused with the state
                                                                      # 'jordan',
                                                                      # 'kazakhstan',
                                                                      # 'kenya',
                                                                      # 'kiribati',
        'korea, democratic people\'s republic of' => 'north korea',
        'korea, republic of'                      => 'south korea',

        # 'kuwait',
        # 'kyrgyzstan',
        'lao people\'s democratic republic' => 'laos',

        # 'latvia',
        # 'lebanon',
        # 'lesotho',
        # 'liberia',
        'libyan arab jamahiriya' => 'libya',

        # 'liechtenstein',
        # 'lithuania',
        # 'luxembourg',
        # 'macao',
        'macedonia, the former yugoslav republic of' => 'macedonia',

        # 'madagascar',
        # 'malawi',
        # 'malaysia',
        # 'maldives',
        # 'mali',
        # 'malta',
        # 'marshall islands',
        # 'martinique',
        # 'mauritania',
        # 'mauritius',
        # 'mayotte',
        # 'mexico',
        'micronesia, federated states of' => 'micronesia',
        'moldova, republic of'            => 'moldova',

        # 'monaco',
        # 'mongolia',
        # 'montenegro',
        # 'montserrat',
        # 'morocco',
        # 'mozambique',
        # 'myanmar',
        # 'namibia',
        # 'nauru',
        # 'nepal',
        # 'netherlands',
        'netherlands antilles' => -1,
        'new caledonia'        => 'caledonia',
        'new zealand'          => 'zealand',

        # 'nicaragua',
        # 'niger',
        # 'nigeria',
        # 'niue',
        # 'norfolk island',
        'northern mariana islands' => -1,

        # 'norway',
        # 'oman',
        # 'pakistan',
        # 'palau',
        'palestinian territory, occupied' => 'palestine',

        # 'panama',
        'papua new guinea' => 'papua guinea',

        # 'paraguay',
        # 'peru',
        # 'philippines',
        # 'pitcairn',
        # 'poland',
        # 'portugal',
        # 'puerto rico',
        # 'qatar',
        'reunion' => -1,

        # 'romania',
        'russian federation' => 'russia',

        # 'rwanda',
        'saint barthelemy'                             => -1,
        'saint helena, ascension and tristan da cunha' => -1,
        'saint kitts and nevis'                        => -1,
        'saint lucia'                                  => -1,
        'saint-martin (french part)'                   => -1,
        'saint pierre and miquelon'                    => -1,
        'saint vincent and the grenadines'             => -1,

        # 'samoa',
        'san marino'            => -1,
        'sao tome and principe' => -1,

        # 'saudi arabia',
        # 'senegal',
        # 'serbia',
        # we should be able to delete the next line
        'serbia and montenegro' => 'serbia montenegro',

        # 'seychelles',
        # 'sierra leone',
        'sint maarten (dutch part)' => -1,

        # 'singapore',
        # 'slovakia',
        # 'slovenia',
        # 'solomon islands',
        # 'somalia',
        'south africa'                                 => 'africa south',
        'south georgia and the south sandwich islands' => -1,

        # 'spain',
        # 'sri lanka',
        # 'sudan',
        # 'suriname',
        'svalbard and jan mayen' => -1,

        # 'swaziland',
        # 'sweden',
        # 'switzerland',
        'syrian arab republic' => 'syria',

        'taiwan, province of china' => 'taiwan',

        # 'tajikistan',
        'tanzania, united republic of' => 'tanzania',

        # 'thailand',
        # 'timor-leste' => -1,
        # 'togo',
        # 'tokelau',
        # 'tonga',
        'trinidad and tobago' => 'trinidad',

        # 'tunisia',
        # 'turkey',
        # 'turkmenistan',
        'turks and caicos islands' => -1,

        # 'tuvalu',
        # 'uganda',
        # 'ukraine',
        'united arab emirates' => 'emirates arab',

        # 'united kingdom',
        # 'united states',
        'united states minor outlying islands' => -1,

        # 'uruguay',
        # 'uzbekistan',
        # 'vanuatu',
        'venezuela, bolivarian republic of' => 'venezuela',
        'viet nam'                          => 'vietnam',

        'virgin islands, british' => -1,
        'virgin islands, u.s.'    => -1,

        'wallis and futuna' => 'futuna',
        'western sahara'    => 'sahara western',

        # 'yemen',
        # 'zambia',
        # 'zimbabwe',
    };

}

1;
