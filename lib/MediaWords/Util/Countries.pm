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
    'bolivia, plurinational state of' => 'bolivia',
    'bosnia and herzegovina' => 'bosnia',

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
    'christmas island' => -1,
    'cocos (keeling) islands' => -1,

    # 'colombia',
    # 'comoros',
    # 'congo',
    'congo, the democratic republic of the' => 'congo republic',

    'cook islands' => -1,
    # 'costa rica',
    # 'cote d\'ivoire',
    # 'croatia',
    # 'cuba',
    # 'cyprus',
    # 'czech republic',
    # 'denmark',
    # 'djibouti',
    'dominica' => -1,
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

    'french guiana' => 'guiana french',
    'french polynesia' => 'polynesia french',
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
    'moldova, republic of' => 'moldova',
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
    'new caledonia' => 'caledonia',
    'new zealand' => 'zealand',
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
    'papua new guinea' => 'papua guina',
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
    'saint barthelemy' => -1,
    'saint helena, ascension and tristan da cunha' => -1,
    'saint kitts and nevis'                        => -1,
    'saint lucia' => -1,
    'saint martin' => -1,
    'saint pierre and miquelon'        => -1,
    'saint vincent and the grenadines' => -1,

    # 'samoa',
    'san marino' => -1,
    'sao tome and principe' => -1,

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
    'south africa' => 'africa south',
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
    'tanzania, united republic of' => 'tanznia',
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
    'viet nam'                => 'vietnam',
    'virgin islands, british' => -1,
    'virgin islands, u.s.'    => -1,
    'wallis and futuna'       => 'futuna',
    'western sahara' => 'sahara western',
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

    die ( "country has more than two terms: '$country'" ) if ( @country_split > 2 );

    return $stemmer->stem( @country_split );
}

sub get_country_data_base_value
{
    my ( $country ) = @_;

    return join( ' ', @{ get_stemmed_country_terms( $country ) } );
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
