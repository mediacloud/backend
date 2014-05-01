package MediaWords::Util::Config;
use Modern::Perl "2013";
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
use Hash::Merge;

# cache config object so that it remains the same from call to call
my $_config;

# base dir
my $MC_ROOT_DIR;
my $_base_dir = __DIR__ . '/../../..';


BEGIN
{
    use File::Basename;

    use File::Spec;

    my $file_dir = dirname( __FILE__ );

    use Cwd qw( realpath );

    my $source_rt = "$file_dir" . "/../../../";

    use File::Spec;

    $MC_ROOT_DIR = realpath( File::Spec->canonpath( $source_rt ) );
}

sub get_mc_root_dir
{
    return $MC_ROOT_DIR;
}

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

sub _parse_config_file
{
    my $config_file = shift;

    -r $config_file or croak "Can't read from $config_file";

    #print "config:file: $config_file\n";
    my $ret = Config::Any->load_files( { files => [ $config_file ], use_ext => 1 } )->[ 0 ]->{ $config_file };

    return $ret;
}

# set the cached config object given a file path
sub set_config_file
{
    my $config_file = shift;

    -r $config_file or croak "Can't read from $config_file";

    #print "config:file: $config_file\n";
    set_config( _parse_config_file( $config_file ) );
}

# set the cached config object
sub set_config
{
    my ( $config ) = @_;

    if ( $_config )
    {
        carp( "config object already cached" );
    }

    _set_dynamic_defaults( $config );

    my $static_defaults = _read_static_defaults();

    my $merge = Hash::Merge->new( 'LEFT_PRECEDENT' );

    #Work around bug in Hash::Merge::merge in which it modifies $@
    my $appersand = $@;
    my $merged = $merge->merge( $config, $static_defaults );

    $@ = $appersand;

    $_config = $merged;

    verify_settings( $_config );
}

sub _read_static_defaults
{
    my $defaults_file_yml = get_mc_root_dir() . '/config/defaults.yml';

    my $static_defaults = _parse_config_file( $defaults_file_yml );

    return $static_defaults;
}

# die() if obsolete configuration syntax is being used
sub _croak_on_obsolete_configuration_syntax($)
{
    my $config = shift;

    # Ensure that the new MongoDB GridFS configuration syntax is being used
    if (
        $config->{ mongodb_gridfs }
        and (  $config->{ mongodb_gridfs }->{ mediawords }
            or $config->{ mongodb_gridfs }->{ test }->{ database }
            or ( !$config->{ mongodb_gridfs }->{ host } )
            or ( !$config->{ mongodb_gridfs }->{ port } )
            or ( !$config->{ mongodb_gridfs }->{ downloads } ) )
      )
    {

        my $error_message = <<"EOF";
MongoDB GridFS configuration syntax in mediawords.yml has been changed from:

    ### MongoDB connection settings for storing downloads in GridFS
    mongodb_gridfs:
        ### Production database
        mediawords:
            host      : "localhost"
            port      : "27017"
            database  : "mediacloud_downloads_gridfs"
        ### Testing database
        test:
            host      : "localhost"
            port      : "27017"
            database  : "mediacloud_downloads_gridfs_test"

to:

    ### MongoDB connection settings
    mongodb_gridfs:
        host : "localhost"
        port : "27017"
        ### Database for storing raw downloads
        downloads:
            database_name : "mediacloud_downloads_gridfs"
        ### Database for testing
        test:
            database_name : "mediacloud_downloads_gridfs_test"

Please update your mediawords.yml accordingly (use mediawords.yml.dist as an example).
EOF
        croak $error_message;
    }

    # Ensure that the new Amazon S3 configuration syntax is being used
    if (
        $config->{ amazon_s3 }
        and (  $config->{ amazon_s3 }->{ mediawords }
            or $config->{ amazon_s3 }->{ test }->{ downloads_folder_name }
            or ( !$config->{ amazon_s3 }->{ downloads } )
            or ( !$config->{ amazon_s3 }->{ downloads }->{ directory_name } ) )
      )
    {

        my $error_message = <<"EOF";
Amazon S3 configuration syntax in mediawords.yml has been changed from:

    ### Amazon S3 connection settings
    amazon_s3:

        ### Authentication credentials
        access_key_id       : "AKIAIOSFODNN7EXAMPLE"
        secret_access_key   : "wJalrXUtnFEMI/K7MDENG/bPxRfiCYzEXAMPLEKEY"

        ### Production bucket
        mediawords:
            bucket_name             : "mediacloud"
            downloads_folder_name   : "downloads"

        ### Testing bucket
        test:
            bucket_name             : "mediacloud_test"
            downloads_folder_name   : "downloads_test"

to:

    ### Amazon S3 connection settings
    amazon_s3:

        ### Authentication credentials
        access_key_id       : "AKIAIOSFODNN7EXAMPLE"
        secret_access_key   : "wJalrXUtnFEMI/K7MDENG/bPxRfiCYzEXAMPLEKEY"

        ### Bucket for storing downloads
        downloads:
            bucket_name    : "mediacloud"
            directory_name : "downloads"

        ### Bucket for testing
        test:
            bucket_name    : "mediacloud_test"
            directory_name : "downloads_test"

Please update your mediawords.yml accordingly (use mediawords.yml.dist as an example).
EOF
        croak $error_message;
    }
}

sub verify_settings
{
    my ( $config ) = @_;

    defined( $config->{ database } ) or croak "No database connections configured";

    _croak_on_obsolete_configuration_syntax( $config );
}

sub _set_dynamic_defaults
{
    my ( $config ) = @_;

    $config->{ mediawords }->{ script_dir } ||= "$_base_dir/script";
    $config->{ mediawords }->{ data_dir }   ||= "$_base_dir/data";
    $config->{ session }->{ storage }       ||= "$ENV{HOME}/tmp/mediacloud-session";

    my $auth = {
        default_realm => 'users',
        users         => {
            credential => {
                class              => 'Password',
                password_field     => 'password',
                password_type      => 'salted_hash',
                password_hash_type => 'SHA-256',
                password_salt_len  => 64
            },
            store => { class => 'MediaWords' }
        }
    };
    $config->{ 'Plugin::Authentication' } ||= $auth;

    return $config;
}

1;
