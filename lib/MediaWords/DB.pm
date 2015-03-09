package MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;

use Carp;
use List::Util qw( first );

use DBIx::Simple::MediaWords;

use MediaWords::Util::Config;

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

sub connect_to_db(;$$)
{
    my ( $label, $do_not_check_schema_version ) = @_;

    my $ret = DBIx::Simple::MediaWords->connect( connect_info( $label ), $do_not_check_schema_version );

    die "Error in connect_to_db $@" unless defined( $ret );

    my $config = MediaWords::Util::Config::get_config();

    if ( defined( $config->{ mediawords }->{ db_statement_timeout } ) )
    {
        $ret->query( " SET statement_timeout TO ? ", $config->{ mediawords }->{ db_statement_timeout } );
    }

    # Reset the session variable in case the database connection is being reused due to pooling.

    my $query = <<'END_SQL';
DO $$ 
BEGIN
PERFORM enable_story_triggers();
EXCEPTION 
WHEN undefined_function THEN
    -- This exception will be raised if the database is uninitialized at this point.
    -- So, don't emit any kind of error because of an non-existent function.
    NULL;
WHEN OTHERS THEN
    -- Forward the exception
    RAISE;
END
$$;

END_SQL

    $ret->query( $query );

    return $ret;
}

sub connect_settings
{
    my ( $label ) = @_;

    # If this is Catalyst::Test run, force the label to the test database
    if ( $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } )
    {
        print STDERR "Using the 'test' database\n";
        $label = 'test';
    }

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

sub get_db_labels
{
    my $all_settings = MediaWords::Util::Config::get_config->{ database };

    defined( $all_settings ) or croak( "No database connections configured" );

    my @labels = map { $_->{ label } } @{ $all_settings };

    return @labels;
}

sub _set_environment_vars_for_db
{
    my ( $label ) = @_;

    my $connect_settings = connect_settings( $label );

    $ENV{ 'PGPASSWORD' } = $connect_settings->{ pass };
    $ENV{ 'PGPORT' }     = $connect_settings->{ port };
    $ENV{ 'PGHOST' }     = $connect_settings->{ host };
    $ENV{ 'PGDATABASE' } = $connect_settings->{ db };
    $ENV{ 'PGUSER' }     = $connect_settings->{ user };
}

sub exec_psql_for_db
{
    my ( $label, @ARGS ) = @_;

    _set_environment_vars_for_db( $label );

    exec( 'psql', @ARGS );
    die 'exec failed';
}

sub print_shell_env_commands_for_psql
{
    my ( $label, @ARGS ) = @_;

    _set_environment_vars_for_db( $label );

    my $psql_env_vars = [ qw ( PGPASSWORD PGHOST PGDATABASE PGUSER PGPORT) ];

    foreach my $psql_env_var ( @{ $psql_env_vars } )
    {
        say "export $psql_env_var=" . $ENV{ $psql_env_var };
    }
}

sub authenticate
{
    my ( $self, $label ) = @_;

    return __PACKAGE__->connect( connect_info( $label ) );
}

sub run_block_with_large_work_mem( &$ )
{

    my $block = shift;
    my $db    = shift;

    DBIx::Simple::MediaWords::run_block_with_large_work_mem { $block->() } $db;
}

# You can replace this text with custom content, and it will be preserved on regeneration
1;

