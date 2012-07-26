package MediaWords::Util::Config;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# Parse and return data from mediawords.yml config file.

# This code should be used instead of MediaWords->config in general, b/c
# MediaWords::Util::Config::get_config will work both from within and without
# catalyst (for instance in stand alone command line scripts).

# in the catalyst case, the core MediaWords script calls the set_config
# function to set the returned config object to the already generated
# config object for the app.

use strict;

use Carp;
use Dir::Self;
use Config::Any;

# cache config object so that it remains the same from call to call
my $_config;

# base dir
my $_base_dir = __DIR__ . '/../../..';

sub get_config
{

    if ( $_config )
    {
        return $_config;
    }

    # TODO: This should be standardized
    set_config_file( $_base_dir . '/mediawords.yml' );

    return $_config;
}

# set the cached config object given a file path
sub set_config_file
{
    my $config_file = shift;

    -r $config_file or croak "Can't read from $config_file";

    #print "config:file: $config_file\n";
    set_config( Config::Any->load_files( { files => [ $config_file ], use_ext => 1 } )->[ 0 ]->{ $config_file } );
}

# set the cached config object
sub set_config
{
    my ( $config ) = @_;

    if ( $_config )
    {
        carp( "config object already cached" );
    }

    $_config = set_defaults( $config );

    verify_settings( $_config );
}

sub set_defaults
{
    my ( $config ) = @_;

    $config->{ mediawords }->{ script_dir } ||= "$_base_dir/script";
    $config->{ mediawords }->{ data_dir }   ||= "$_base_dir/data";
    $config->{ session }->{ storage }       ||= "$ENV{HOME}/tmp/mediacloud-session";

    return $config;
}

sub verify_settings
{
    my ( $config ) = @_;

    defined( $config->{ database } ) or croak "No database connections configured";
}

1;
