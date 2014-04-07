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

# cache config object so that it remains the same from call to call
my $_config;

# base dir
my $_base_dir = __DIR__ . '/../../..';

sub base_dir
{
    return $_base_dir;
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

    my $static_defaults = _read_static_defaults();

    my $merge = Hash::Merge->new('LEFT_PRECEDENT');

    my $merged = $merge->merge( $config, $static_defaults );

    _set_dynamic_defaults( $merged );

    $_config = $merged;

    verify_settings( $_config );
}

# sub _dump_defaults_as_yaml
# {
#     my $empty_config = {};

#     _set_defaults( $empty_config );

#     use YAML;
#     local $YAML::Indent = 4;
#     YAML::DumpFile( '/tmp/default.yml', $empty_config );
# }

sub _read_static_defaults
{
    my $defaults_file_yml = base_dir() . '/config/defaults.yml';

    my $static_defaults = _parse_config_file( $defaults_file_yml );

    return $static_defaults;
}

# sub _set_defaults
# {
#     my ( $config ) = @_;

#     $config->{ mediawords }->{ script_dir }                       ||= "$_base_dir/script";
#     $config->{ mediawords }->{ data_dir }                         ||= "$_base_dir/data";
#     $config->{ mediawords }->{ language }                         ||= "en_US_and_ru_RU";
#     $config->{ mediawords }->{ user_agent }                       ||= "mediawords bot (http://cyber.law.harvard.edu)";
#     $config->{ mediawords }->{ owner }                            ||= "mediacloud\@cyber.law.harvard.edu";
#     $config->{ mediawords }->{ always_show_stack_traces }         ||= "no";
#     $config->{ mediawords }->{ disable_json_top_500_words_cache } ||= "no";
#     $config->{ mediawords }->{ default_home_page }                ||= "admin/media/list";
#     $config->{ mediawords }->{ recaptcha_public_key }             ||= "6LfEVt0SAAAAAFwQI0pOZ1bTHgDTpQcMeQY6VLd_";
#     $config->{ mediawords }->{ recaptcha_private_key }            ||= "6LfEVt0SAAAAABmI-8IJmx4g93eNcSeyeCxvLMs2";
#     $config->{ mediawords }->{ download_storage_locations }       ||= [ 'postgresql' ];
#     $config->{ mediawords }->{ read_tar_downloads_from_gridfs }   ||= 'no';
#     $config->{ mediawords }->{ read_file_downloads_from_gridfs }  ||= 'no';
#     $config->{ mediawords }->{ extractor_method }                 ||= 'CrfExtractor';
#     $config->{ mediawords }->{ controversy_model_reps }           ||= '25';
#     $config->{ mediawords }->{ solr_select_url }                  ||= 'http://localhost:8983/solr/collection1/select';
#     $config->{ mediawords }->{ inline_java_jni }                  ||= 'no';

#     $config->{ mail }->{ from_address } ||= "noreply\@mediacloud.org";
#     $config->{ mail }->{ bug_email }    ||= "";
#     $config->{ session }->{ storage }   ||= "$ENV{HOME}/tmp/mediacloud-session";

#     # Gearman
#     $config->{ gearman }->{ worker_log_dir }                    ||= 'data/gearman_worker_logs/';
#     $config->{ gearman }->{ notifications }->{ emails }         ||= [];
#     $config->{ gearman }->{ notifications }->{ from_address }   ||= 'gjs@mediacloud.org';
#     $config->{ gearman }->{ notifications }->{ subject_prefix } ||= '[GJS]';

#     # Supervisor
#     $config->{ supervisor }->{ childlogdir } ||= 'data/supervisor_logs/';

#     my $auth = {
#         default_realm => 'users',
#         users         => {
#             credential => {
#                 class              => 'Password',
#                 password_field     => 'password',
#                 password_type      => 'salted_hash',
#                 password_hash_type => 'SHA-256',
#                 password_salt_len  => 64
#             },
#             store => { class => 'MediaWords' }
#         }
#     };
#     $config->{ 'Plugin::Authentication' } ||= $auth;

#     return $config;
# }

sub verify_settings
{
    my ( $config ) = @_;

    defined( $config->{ database } ) or croak "No database connections configured";
}

sub _set_dynamic_defaults
{
    my ( $config ) = @_;

    $config->{ mediawords }->{ script_dir }                       ||= "$_base_dir/script";
    $config->{ mediawords }->{ data_dir }                         ||= "$_base_dir/data";
    $config->{ session }->{ storage }   ||= "$ENV{HOME}/tmp/mediacloud-session";

    return $config;
}

1;
