package MediaWords::Util::Countries;

use Moose;
use strict;
use warnings;

use Perl6::Say;
use Data::Dumper;
use MediaWords::Pg;
use Locale::Country;
my $_country_name_remapping = {

    # 'afghanistan',
    # 'aland islands',
    # 'albania',
    # 'algeria',
    # 'american samoa',
    # 'andorra',
    # 'angola',
    # 'anguilla',
    # 'antarctica',
    'antigua and barbuda' => 'antigua barbuda',

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
    # 'bolivia, plurinational state of',
    'bosnia and herzegovina' => 'bosnia herzegovina',

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
    # 'cape verde',
    # 'cayman islands',
    # 'central african republic',
    # 'chad',
    # 'chile',
    # 'china',
    # 'christmas island',
    'cocos (keeling) islands' => 'cocos keeling islands',

    # 'colombia',
    # 'comoros',
    # 'congo',
    'congo, the democratic republic of the' => 'democratic republic congo',

    # 'cook islands',
    # 'costa rica',
    # 'cote d\'ivoire',
    # 'croatia',
    # 'cuba',
    # 'cyprus',
    # 'czech republic',
    # 'denmark',
    # 'djibouti',
    # 'dominica',
    # 'dominican republic',
    # 'ecuador',
    # 'egypt',
    # 'el salvador',
    # 'equatorial guinea',
    # 'eritrea',
    # 'estonia',
    # 'ethiopia',
    'falkland islands (malvinas)' => 'falkland islands',

    # 'faroe islands',
    # 'fiji',
    # 'finland',
    # 'france',
    'france, metropolitan' => -1,

    # 'french guiana',
    # 'french polynesia',
    # 'french southern territories',
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
    'heard island and mcdonald islands' => 'heard island mcdonald',
    'holy see (vatican city state)'     => 'holy see',

    # 'honduras',
    # 'hong kong',
    # 'hungary',
    # 'iceland',
    # 'india',
    # 'indonesia',
    'iran, islamic republic of' => 'iran',

    # 'iraq',
    # 'ireland',
    'isle of man' => 'isle man',

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
    'lao people\'s democratic republic' => 'lao',

    # 'latvia',
    # 'lebanon',
    # 'lesotho',
    # 'liberia',
    'libyan arab jamahiriya' => 'libya',

    # 'liechtenstein',
    # 'lithuania',
    # 'luxembourg',
    # 'macao',
    # 'macedonia, the former yugoslav republic of',
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
    # 'micronesia, federated states of',
    # 'moldova, republic of',
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
    # 'netherlands antilles',
    # 'new caledonia',
    # 'new zealand',
    # 'nicaragua',
    # 'niger',
    # 'nigeria',
    # 'niue',
    # 'norfolk island',
    # 'northern mariana islands',
    # 'norway',
    # 'oman',
    # 'pakistan',
    # 'palau',
    # 'palestinian territory, occupied',
    # 'panama',
    # 'papua new guinea',
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
    # 'saint barthelemy',
    'saint helena, ascension and tristan da cunha' => -1,
    'saint kitts and nevis'                        => 'saint kitts nevis',

    # 'saint lucia',
    # 'saint martin',
    'saint pierre and miquelon'        => 'saint pierre miquelon',
    'saint vincent and the grenadines' => 'saint vincent grenadines',

    # 'samoa',
    # 'san marino',
    'sao tome and principe' => 'sao tome principe',

    # 'saudi arabia',
    # 'senegal',
    # 'serbia',
    # 'seychelles',
    # 'sierra leone',
    # 'singapore',
    # 'slovakia',
    # 'slovenia',
    # 'solomon islands',
    # 'somalia',
    # 'south africa',
    'south georgia and the south sandwich islands' => -1,

    # 'spain',
    # 'sri lanka',
    # 'sudan',
    # 'suriname',
    'svalbard and jan mayen' => 'svalbard jan mayen',

    # 'swaziland',
    # 'sweden',
    # 'switzerland',
    'syrian arab republic' => 'syria',

    # 'taiwan, province of china',
    # 'tajikistan',
    # 'tanzania, united republic of',
    # 'thailand',
    # 'timor-leste',
    # 'togo',
    # 'tokelau',
    # 'tonga',
    'trinidad and tobago' => 'trinidad tobago',

    # 'tunisia',
    # 'turkey',
    # 'turkmenistan',
    'turks and caicos islands' => 'turks caicos islands',

    # 'tuvalu',
    # 'uganda',
    # 'ukraine',
    # 'united arab emirates',
    # 'united kingdom',
    # 'united states',
    'united states minor outlying islands' => -1,

    # 'uruguay',
    # 'uzbekistan',
    # 'vanuatu',
    # 'venezuela, bolivarian republic of',
    'viet nam'                => 'vietnam',
    'virgin islands, british' => 'british virgin islands',
    'virgin islands, u.s.'    => -1,
    'wallis and futuna'       => 'wallis futuna',

    # 'western sahara',
    # 'yemen',
    # 'zambia',
    # 'zimbabwe',
};

sub _get_non_remapped_names_for_non_banned_countries
{
    my $all_countries = [ sort map { lc } Locale::Country::all_country_names ];

    #remove banned country names
    $all_countries =
      [ grep { ( !defined( $_country_name_remapping->{ $_ } ) ) || $_country_name_remapping->{ $_ } ne '-1' }
          @$all_countries ];

}

sub _remap_name_if_necessary
{
    my ( $country_name ) = @_;

    if ( defined( $_country_name_remapping->{ $country_name } ) )
    {
        return $_country_name_remapping->{ $country_name };
    }
    else
    {
        return $country_name;
    }
}

sub _get_updated_country_name
{
    my ( $country_name ) = @_;

    $country_name = _remap_name_if_necessary( $country_name );

    $country_name =~ s/\,.*//g;

    return $country_name;
}

sub get_countries_for_counts
{
    my $all_countries = _get_non_remapped_names_for_non_banned_countries();

    $all_countries = [ map { _get_updated_country_name( $_ ) } @$all_countries ];

    $all_countries = [ sort @$all_countries ];
    return $all_countries;
}

my $_country_code_for_stemmed_country_name;

sub get_stemmed_country_terms
{
    my ( $country ) = @_;

    my $stemmer = MediaWords::Util::Stemmer->new;

    my @country_split = split ' ', $country;

    die if scalar( @country_split ) > 3;

    #say $country;

    #say Dumper (@country_split);
    #say Dumper ([$stemmer->stem( @country_split )]);

    #$DB::single = 2;
    my ( $country_term1, $country_term2, $country_term3 ) = @{ $stemmer->stem( @country_split ) };

    #say STDERR Dumper([($country_term1, $country_term2)]);

    #exit;
    if ( !defined( $country_term2 ) )
    {
        $country_term2 = $country_term1;
    }

    if ( !defined( $country_term3 ) )
    {
        $country_term3 = $country_term1;
    }

    return ( $country_term1, $country_term2, $country_term3 );
}

sub get_country_data_base_value
{
    my ( $country ) = @_;

    my ( $country_term1, $country_term2, $country_term3 ) = get_stemmed_country_terms( $country );
    my $country_data_base_value = ( $country_term1 eq $country_term2 ) ? $country_term1 : "$country_term1 $country_term2";

    if ( $country_term3 ne $country_term1 )
    {
        $country_data_base_value .= " $country_term3";
    }

    return $country_data_base_value;
}

sub get_country_code_for_stemmed_country_name
{
    my ( $stemmed_country_name ) = @_;

    if ( !defined( $_country_code_for_stemmed_country_name ) )
    {
        my $non_remapped_names = _get_non_remapped_names_for_non_banned_countries();
        $_country_code_for_stemmed_country_name =
          { map { get_country_data_base_value( _get_updated_country_name( $_ ) ) => Locale::Country::country2code( $_ ) }
              @$non_remapped_names };

        #say STDERR Dumper($_country_code_for_stemmed_country_name);
    }

    my $ret = $_country_code_for_stemmed_country_name->{ $stemmed_country_name };

    $ret = uc( $ret );

    die "Country code for $stemmed_country_name not found in " . Dumper( $_country_code_for_stemmed_country_name )
      unless $ret;
    return $ret;
}

1;
