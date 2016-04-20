package MediaWords::Util::Config;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

# Parse and return data from mediawords.yml config file.

# This code should be used instead of MediaWords->config in general, b/c
# MediaWords::Util::Config::get_config will work both from within and without
# catalyst (for instance in stand alone command line scripts).

# in the catalyst case, the core MediaWords script calls the set_config
# function to set the returned config object to the already generated
# config object for the app.

use Carp;
use Config::Any;
use Dir::Self;
use Exporter 'import';
use Hash::Merge;

# cache config object so that it remains the same from call to call
my $_config;

# base dir
my $MC_ROOT_DIR;
my $_base_dir = __DIR__ . '/../../..';

our @EXPORT_OK = qw(get_config);

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

# merge configs using Hash::Merge, with precedence for the mediawords.yml config.
# use a Hash::Merge object with a custom behavior set to the same as
# LEFT_PRECEDENT but that replaces arrays instead of merging them.
sub _merge_configs
{
    my ( $config, $static_defaults ) = @_;

    my $merge = Hash::Merge->new();

    # this is just copy and pasted from Hash::Merge with one line different.  annoyingly,
    # there's no way to get the behavior hash out of Hash::Merge directly to just modify it.
    $merge->specify_behavior(
        {
            'SCALAR' => {
                'SCALAR' => sub { $_[ 0 ] },
                'ARRAY'  => sub { $_[ 0 ] },
                'HASH'   => sub { $_[ 0 ] },
            },
            'ARRAY' => {
                'SCALAR' => sub { [ @{ $_[ 0 ] }, $_[ 1 ] ] },

                # this is the only difference between our custom behavior and LEFT_PRECEDENT
                'ARRAY' => sub { $_[ 0 ] },
                'HASH'  => sub { [ @{ $_[ 0 ] }, values %{ $_[ 1 ] } ] },
            },
            'HASH' => {
                'SCALAR' => sub { $_[ 0 ] },
                'ARRAY'  => sub { $_[ 0 ] },
                'HASH'   => sub { Hash::Merge::_merge_hashes( $_[ 0 ], $_[ 1 ] ) },
            }
        },
        'custom'
    );

    # work around bug in Hash::Merge::merge in which it modifies $@
    my $ampersand = $@;

    my $merged = $merge->merge( $config, $static_defaults );

    $@ = $ampersand;

    return $merged;
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

    $_config = _merge_configs( $config, $static_defaults );

    verify_settings( $_config );
}

sub _read_static_defaults
{
    my $defaults_file_yml = get_mc_root_dir() . '/config/defaults.yml';

    my $static_defaults = _parse_config_file( $defaults_file_yml );

    return $static_defaults;
}

sub verify_settings
{
    my ( $config ) = @_;

    defined( $config->{ database } ) or croak "No database connections configured";

    # Warn if there's a foreign database set for storing raw downloads
    if ( grep { $_->{ label } eq 'raw_downloads' } @{ $config->{ database } } )
    {
        # For whatever reason WARN() doesn't get imported from ::CommonLibs
        MediaWords::CommonLibs::WARN(
            <<EOF

You have a foreign database set for storing raw downloads as
/database/label[raw_downloads].

Storing raw downloads in a foreign database is no longer supported so please
remove database connection credentials with label "raw_downloads".

EOF
        );
    }
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
