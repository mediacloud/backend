package MediaWords::DB;
use MediaWords::CommonLibs;


use strict;
use warnings;

use Carp;
use List::Util qw( first );

use DBIx::Simple::MediaWords;

use MediaWords::Util::Config;

use base 'DBIx::Class::Schema';

__PACKAGE__->load_classes;

# Created by DBIx::Class::Schema::Loader v0.04999_02 @ 2008-03-06 18:46:45
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:wXcXYixAy0uBrYdHuKCPag

my $_connect_settings;

# takes a hashref to a hash of settings and returns an array
#  with DBI connect info
sub _create_connect_info_from_settings
{
    my ( $settings ) = @_;
    my $data_source = 'dbi:Pg:dbname=' . $settings->{ db } . ';host=' . $settings->{ host };

    if ( defined( $settings->{ port } ) )
    {
        $data_source .= ';port=' . $settings->{ port };
    }

    return (
        $data_source,
        $settings->{ user },
        $settings->{ pass },
        {
            AutoCommit     => 1,
            pg_enable_utf8 => 1,
            RaiseError     => 1
        }
    );
}

# returns connection info from the configuration file
# if no connection label is supplied and no connections have been made,
# the first connection in the config is used otherwise the last used settings
# are returned
sub connect_info
{
    my ( $label ) = @_;

    my $settings = connect_settings( $label );

    return _create_connect_info_from_settings( $settings );
}

sub connect_to_db
{
    my ( $label ) = @_;

    my $ret = DBIx::Simple::MediaWords->connect( connect_info( $label ) );

    die "Error in connect_to_db $@" unless defined( $ret);

    my $config = MediaWords::Util::Config::get_config();

    if ( defined ( $config->{mediawords}->{ db_statement_timeout } ) )
    {
	$ret->query( " SET statement_timeout TO ? " , $config->{mediawords}->{ db_statement_timeout } );
    }

    return $ret;
}

sub connect_settings
{
    my ( $label ) = @_;

    my $all_settings = MediaWords::Util::Config::get_config->{ database };

    defined( $all_settings ) or croak( "No database connections configured" );

    if ( defined( $label ) )
    {
        $_connect_settings = first { $_->{ label } eq $label } @{ $all_settings }
          or croak "No database connection settings labeled '$label'";
    }

    if ( !defined( $_connect_settings ) )
    {
        $_connect_settings = $all_settings->[ 0 ];
    }

    return $_connect_settings;
}

sub authenticate
{
    my ( $self, $label ) = @_;

    return __PACKAGE__->connect( connect_info( $label ) );
}

# You can replace this text with custom content, and it will be preserved on regeneration
1;

