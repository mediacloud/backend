package MediaWords::Util::Countries;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Moose;
use strict;
use warnings;

use Data::Dumper;
use Carp;
use MediaWords::Languages::Language;
use utf8;

sub _get_non_remapped_names_for_non_banned_countries($)
{
    my $language_code = shift;

    my $lang = MediaWords::Languages::Language::language_for_code( $language_code );
    die "Invalid language code '$language_code'.\n" unless ( $lang );

    my $lcm = $lang->get_locale_codes_api_object();
    my $all_countries = [ sort map { lc } $lcm->all_country_names ];

    my $country_name_remapping = $lang->get_country_name_remapping();

    #remove banned country names
    $all_countries =
      [ grep { ( !defined( $country_name_remapping->{ $_ } ) ) || $country_name_remapping->{ $_ } ne '-1' }
          @$all_countries ];

}

sub _remap_name_if_necessary($$)
{
    my ( $country_name, $language_code ) = @_;

    my $lang = MediaWords::Languages::Language::language_for_code( $language_code );
    die "Invalid language code '$language_code'.\n" unless ( $lang );

    my $country_name_remapping = $lang->get_country_name_remapping();

    if ( defined( $country_name_remapping->{ $country_name } ) )
    {
        return $country_name_remapping->{ $country_name };
    }
    else
    {
        return $country_name;
    }
}

sub _get_updated_country_name($$)
{
    my ( $country_name, $language_code ) = @_;

    $country_name = _remap_name_if_necessary( $country_name, $language_code );

    $country_name =~ s/\,.*//g;

    return $country_name;
}

sub get_countries_for_counts($)
{
    my $language_code = shift;

    my $all_countries = _get_non_remapped_names_for_non_banned_countries( $language_code );

    $all_countries = [ map { _get_updated_country_name( $_, $language_code ) } @$all_countries ];

    $all_countries = [ sort @$all_countries ];
    return $all_countries;
}

my $_country_code_for_stemmed_country_name;

sub get_stemmed_country_terms($$)
{
    my ( $country, $language_code ) = @_;

    my $lang = MediaWords::Languages::Language::language_for_code( $language_code );
    die "Invalid language code '$language_code'.\n" unless ( $lang );

    my @country_split = @{ $lang->tokenize( $country ) };

    binmode( STDOUT, ":utf8" );
    binmode( STDERR, ":utf8" );

    die( "country has more than two terms: '$country' for language '$language_code'" ) if ( @country_split > 2 );

    return $lang->stem( @country_split );
}

sub _get_country_data_base_value($$)
{
    my ( $country, $language_code ) = @_;

    return join( ' ', @{ get_stemmed_country_terms( $country, $language_code ) } );
}

sub get_country_code_for_stemmed_country_name($$)
{
    my ( $stemmed_country_name, $language_code ) = @_;

    my $lang = MediaWords::Languages::Language::language_for_code( $language_code );
    die "Invalid language code '$language_code'.\n" unless ( $lang );

    my $lcm = $lang->get_locale_codes_api_object();

    if ( !defined( $_country_code_for_stemmed_country_name ) )
    {
        my $non_remapped_names = _get_non_remapped_names_for_non_banned_countries( $language_code );
        $_country_code_for_stemmed_country_name = {
            map {
                _get_country_data_base_value( _get_updated_country_name( $_, $language_code ), $language_code ) =>
                  $lcm->country2code( $_ )
            } @$non_remapped_names
        };

        #say STDERR Dumper($_country_code_for_stemmed_country_name);
    }

    my $ret = $_country_code_for_stemmed_country_name->{ $stemmed_country_name };

    # unless ($ret) {
    #     confess "Country code for $stemmed_country_name not found in " . Dumper( $_country_code_for_stemmed_country_name );
    # }

    $ret = uc( $ret );

    return $ret;
}

1;
