package DBIx::Simple::MediaWords;

# local subclass of DBIx::Simple with some modification for use in media cloud code

use strict;

use Carp;
use IPC::Run3;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MediaWords::Util::SchemaVersion;
use MediaWords::DB;

use Carp;
use Data::Page;
use JSON;

use Encode;

use Data::Dumper;
use Try::Tiny;

use base qw(DBIx::Simple);

# STATICS

# cache of table primary key columns
my $_primary_key_columns = {};

# PID for which the schema version has been checked
my $_schema_version_check_pid;

# METHODS

sub new
{
    my $proto = shift;
    my $class = ref( $proto ) || $proto;

    my $self = $class->SUPER::new();

    bless( $self, $class );

    return $self;
}

sub connect($$$$$;$)
{
    my ( $self, $dsn, $user, $pass, $options, $do_not_check_schema_version ) = @_;

    # If the user didn't clearly (via 'true' or 'false') state whether or not
    # to check schema version, check it once per PID
    unless ( defined $do_not_check_schema_version )
    {
        if ( defined $_schema_version_check_pid and $_schema_version_check_pid == $$ )
        {
            $do_not_check_schema_version = 1;
        }
        else
        {
            $do_not_check_schema_version = 0;
        }
    }

    my $ret = $self->SUPER::connect( $dsn, $user, $pass, $options );

    unless ( $do_not_check_schema_version )
    {

        # It would make sense to check the MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION environment variable
        # at this particular point too, but schema_is_up_to_date() warns the user about schema being
        # too old on every run, and that's supposedly a good thing.

        die "Database schema is not up-to-date.\n" unless $ret->schema_is_up_to_date();
    }

    # If schema is not up-to-date, connect() dies and we don't get to set PID here
    $_schema_version_check_pid = $$;

    return $ret;
}

# Schema is outdated / too new; returns 1 if MC should continue nevertheless, 0 otherwise
sub _should_continue_with_outdated_schema($$$)
{
    my ( $current_schema_version, $target_schema_version, $ignore_schema_version_env_variable ) = @_;

    my $config_ignore_schema_version =
      MediaWords::Util::Config->get_config()->{ mediawords }->{ ignore_schema_version } || '';

    if ( ( $config_ignore_schema_version eq 'yes' ) || exists $ENV{ $ignore_schema_version_env_variable } )
    {
        say STDERR <<"EOF";

The current Media Cloud database schema is older than the schema present in mediawords.sql,
but $ignore_schema_version_env_variable is set so continuing anyway.
EOF
        return 1;

    }
    else
    {

        say STDERR <<"EOF";

################################

The current Media Cloud database schema is not the same as the schema present in mediawords.sql.

The database schema currently running in the database is $current_schema_version,
and the schema version in the mediawords.sql is $target_schema_version.

Please run:

    ./script/run_with_carton.sh ./script/mediawords_upgrade_db.pl --import

to automatically upgrade the database schema to the latest version.

If you want to connect to the Media Cloud database anyway (ignoring the schema version),
set the $ignore_schema_version_env_variable environment variable as such:

    $ignore_schema_version_env_variable=1 ./script/your_script.pl

################################
EOF

        return 0;
    }
}

# Checks if the database schema is up-to-date
sub schema_is_up_to_date
{
    my $self = shift @_;

    my $script_dir = MediaWords::Util::Config->get_config()->{ mediawords }->{ script_dir } || $FindBin::Bin;

    # Check if the database is empty
    my $db_vars_table_exists_query =
      "SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name='database_variables')";
    my @db_vars_table_exists = $self->query( $db_vars_table_exists_query )->flat();
    my $db_vars_table        = $db_vars_table_exists[ 0 ] + 0;
    if ( !$db_vars_table )
    {
        say STDERR "Database table 'database_variables' does not exist, probably the database is empty at this point.";
        return 1;
    }

    # Current schema version
    my $schema_version_query =
      "SELECT value AS schema_version FROM database_variables WHERE name = 'database-schema-version' LIMIT 1";
    my @schema_versions        = $self->query( $schema_version_query )->flat();
    my $current_schema_version = $schema_versions[ 0 ] + 0;
    die "Invalid current schema version.\n" unless ( $current_schema_version );

    # Target schema version
    open SQLFILE, "$script_dir/mediawords.sql" or die $!;
    my @sql = <SQLFILE>;
    close SQLFILE;
    my $target_schema_version = MediaWords::Util::SchemaVersion::schema_version_from_lines( @sql );
    die "Invalid target schema version.\n" unless ( $target_schema_version );

    # Check if the current schema is up-to-date
    Readonly my $ignore_schema_version_env_variable => 'MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION';
    if ( $current_schema_version != $target_schema_version )
    {
        return _should_continue_with_outdated_schema( $current_schema_version, $target_schema_version,
            $ignore_schema_version_env_variable );
    }
    else
    {

        # Things are fine at this point.
        return 1;
    }

}

sub _query_impl
{
    my $self = shift @_;

    my $ret = $self->SUPER::query( @_ );

    return $ret;
}

sub query
{
    my $self = shift @_;

    my $ret;

    eval { $ret = $self->_query_impl( @_ ) };
    if ( $@ )
    {
        Carp::confess( "query error: $@" );
    }

    return $ret;
}

sub get_current_work_mem
{
    my $self = shift @_;

    my ( $ret ) = $self->_query_impl( "SHOW work_mem" )->flat();

    return $ret;
}

sub _get_large_work_mem
{
    my $self = shift @_;

    my $config = MediaWords::Util::Config::get_config;

    my $ret = $config->{ mediawords }->{ large_work_mem };

    if ( !defined( $ret ) )
    {
        $ret = $self->get_current_work_mem();
    }

    return $ret;
}

sub run_block_with_large_work_mem( &$ )
{

    my $block = shift;
    my $db    = shift;

    #say STDERR "starting run_block_with_large_work_mem ";

    #say Dumper( $db );

    my $large_work_mem = $db->_get_large_work_mem();

    my $old_work_mem = $db->get_current_work_mem();

    $db->_set_work_mem( $large_work_mem );

    #say "try";

    #say Dumper( $block );

    try
    {
        $block->();
    }
    catch
    {
        $db->_set_work_mem( $old_work_mem );

        confess $_;
    };

    $db->_set_work_mem( $old_work_mem );

    #say STDERR "exiting run_block_with_large_work_mem ";
}

sub _set_work_mem
{
    my ( $self, $new_work_mem ) = @_;

    $self->_query_impl( "SET work_mem = ? ", $new_work_mem );

    return;
}

sub query_with_large_work_mem
{
    my $self = shift @_;

    my $ret;

    #say STDERR "starting query_with_large_work_mem";

    #say Dumper ( [ @_ ] );

    #    my $block =  { $ret = $self->_query_impl( @_ ) };

    #    say Dumper ( $block );

    my @args = @_;

    run_block_with_large_work_mem
    {
        $ret = $self->_query_impl( @args );
    }
    $self;

    #say Dumper( $ret );
    return $ret;
}

sub query_continue_on_error
{
    my $self = shift @_;

    my $ret = $self->SUPER::query( @_ );

    return $ret;
}

sub query_only_warn_on_error
{
    my $self = shift @_;

    my $ret = $self->SUPER::query( @_ );

    warn "Problem executing DBIx::simple->query(" . scalar( join ",", @_ ) . ") :" . $self->error
      unless $ret;
    return $ret;
}

# get the primary key column for the table
sub primary_key_column
{
    my ( $self, $table ) = @_;

    if ( my $id_col = $_primary_key_columns->{ $table } )
    {
        return $id_col;
    }

    my ( $id_col ) = $self->dbh->primary_key( undef, undef, $table );

    $_primary_key_columns->{ $table } = $id_col;

    return $id_col;
}

# do an id lookup on the table and return a single row match if found
sub find_by_id
{
    my ( $self, $table, $id ) = @_;

    my $id_col = $self->primary_key_column( $table );

    confess "undefined primary key column for table '$table'" unless defined( $id_col );

    return $self->query( "select * from $table where $id_col = ?", $id )->hash;
}

# update the row in the table with the given id
# ignore any fields that start with '_'
sub update_by_id($$$$)
{
    my ( $self, $table, $id, $hash ) = @_;

    delete( $hash->{ submit } );

    my $id_col = $self->primary_key_column( $table );

    my $hidden_values = {};
    for my $k ( grep( /^_/, keys( %{ $hash } ) ) )
    {
        $hidden_values->{ $k } = $hash->{ $k };
        delete( $hash->{ $k } );
    }

    my $r = $self->update( $table, $hash, { $id_col => $id } );

    while ( my ( $k, $v ) = each( %{ $hidden_values } ) )
    {
        $hash->{ $k } = $v;
    }

    return $r;
}

# update the row in the table with the given id
# and make note of the changes that were made
sub update_by_id_and_log($$$$$$$$)
{
    my ( $self, $table, $id, $old_hash, $new_hash, $activity_name, $reason, $username ) = @_;

    # Delete the "reason" from the HTTP parameters as it has already been copied
    # to $reason variable
    delete( $new_hash->{ reason } );

    # Find out which fields were changed
    my @changes;
    foreach my $field_name ( keys %{ $old_hash } )
    {

        # Ignore fields that start with '_' and other form cruft
        unless ( $field_name =~ /^_/ or $field_name eq 'submit' or $field_name eq 'reason' )
        {

            # Might be empty
            if ( defined $new_hash->{ $field_name } and defined $old_hash->{ $field_name } )
            {

                if ( $new_hash->{ $field_name } ne $old_hash->{ $field_name } )
                {

                    # say STDERR "Field '$field_name' was changed from: " . $old_hash->{$field_name} .
                    #     "; to: " . $new_hash->{$field_name};

                    my $change = {
                        field     => $field_name,
                        old_value => $old_hash->{ $field_name },
                        new_value => $new_hash->{ $field_name },
                    };
                    push( @changes, $change );
                }
            }

        }
    }

    # If there are no changes, there is nothing to do
    if ( scalar( @changes ) == 0 )
    {
        say STDERR "Nothing to do.";
        return 1;
    }

    # Start transaction
    $self->dbh->begin_work;

    # Make the change
    my $r = 0;
    eval { $r = $self->update_by_id( $table, $id, $new_hash ); };
    if ( $@ )
    {

        # Update failed
        $self->dbh->rollback;
        die $@;
    }

    require MediaWords::DBI::Activities;

    # Update succeeded, write the activity log
    unless ( MediaWords::DBI::Activities::log_activities( $self, $activity_name, $username, $id, $reason, \@changes ) )
    {
        $self->dbh->rollback;
        die "Logging one of the changes failed: $@";
    }

    # Things went fine at this point, commit
    $self->dbh->commit;

    return $r;
}

# delete the row in the table with the given id
sub delete_by_id
{
    my ( $self, $table, $id ) = @_;

    my $id_col = $self->primary_key_column( $table );

    return $self->query( "delete from $table where $id_col = ?", $id );
}

# insert a row into the database for the given table with the given hash values and return the created row as a hash
sub create
{
    my ( $self, $table, $hash ) = @_;

    delete( $hash->{ submit } );

    eval { $self->insert( $table, $hash ); };

    if ( $@ )
    {
        my $query_error = $@;

        confess "error inserting into table '$table' with object:\n" . Dumper( $hash ) . "\n$query_error";
    }

    my $id;

    eval {
        $id = $self->last_insert_id( undef, undef, $table, undef );

        confess "Could not get last id inserted" if ( !defined( $id ) );
    };

    confess "Error getting last_insert_id $@" if ( $@ );

    my $ret = $self->find_by_id( $table, $id );

    confess "could not find new id '$id' in table '$table' " unless ( $ret );

    return $ret;
}

# run create for the given table, retrieving the given fields from the request object
sub create_from_request
{
    my ( $self, $table, $request, $fields ) = @_;

    my $hash;
    for my $field ( @{ $fields } )
    {
        $hash->{ $field } = $request->param( $field );
    }

    return $self->create( $table, $hash );
}

# select a single row from the database matching the hash or insert
# a row with the hash values and return the inserted row as a hash
sub find_or_create
{
    my ( $self, $table, $hash ) = @_;

    delete( $hash->{ submit } );

    if ( my $row = $self->select( $table, '*', $hash )->hash )
    {
        return $row;
    }
    else
    {
        return $self->create( $table, $hash );
    }

}

# execute the query and return a list of pages hashes
sub query_paged_hashes
{
    my ( $self, $query, $query_params, $page, $rows_per_page ) = @_;

    $page ||= 1;

    my $offset = ( $page - 1 ) * $rows_per_page;

    $query .= " limit ( $rows_per_page + 1 ) offset $offset";

    my $rs = $self->query( $query, @{ $query_params } );

    my $list = [];
    my $i    = 0;
    my $hash;
    while ( ( $hash = $rs->hash ) && ( $i++ < $rows_per_page ) )
    {
        push( @{ $list }, $hash );
    }

    my $max = $offset + $i;
    if ( $hash )
    {
        $max++;
    }

    my $pager = Data::Page->new( $max, $rows_per_page, $page );

    return ( $list, $pager );

}

# executes the supplied subroutine inside a transaction
sub transaction
{
    my ( $self, $tsub, @tsub_args ) = @_;

    $self->query( 'START TRANSACTION' );

    eval {
        if ( $tsub->( @tsub_args ) )
        {
            $self->query( 'COMMIT' );
        }
        else
        {
            $self->query( 'ROLLBACK' );
        }
    };

    if ( my $x = $@ )
    {
        $self->query( 'ROLLBACK' );

        # TODO: This obliterates any stack trace that exists.
        # See <http://stackoverflow.com/questions/971273/perl-sigdie-eval-and-stack-trace>
        die $x;
    }
}

sub query_csv_dump
{
    my ( $self, $output_file, $query, $params, $with_header ) = @_;

    my $copy_statement = "COPY ($query) TO STDOUT WITH CSV ";

    if ( $with_header )
    {
        $copy_statement .= " HEADER";
    }

    my $line;
    $self->dbh->do( $copy_statement, {}, @$params );
    while ( $self->dbh->pg_getcopydata( $line ) >= 0 )
    {
        print $output_file encode( 'utf8', $line );
    }

}

# get the name of a temporary table that contains all of the ids in $ids as an 'id bigint' field.
# the database connection must be within a transaction.  the temporary table is setup to be dropped
# at the end of the current transaction.
sub get_temporary_ids_table ($)
{
    my ( $db, $ids ) = @_;

    my $table = "_tmp_ids_" . int( rand( 100000 ) );
    while ( $db->query( "select 1 from pg_class where relname = ?", $table )->hash )
    {
        $table = "_tmp_ids_" . int( rand( 100000 ) );
    }

    $db->query( "create temporary table $table ( id bigint )" );

    eval { $db->dbh->do( "copy $table from STDIN" ) };
    die( " Error on copy: $@" ) if ( $@ );

    for my $id ( @{ $ids } )
    {
        eval { $db->dbh->pg_putcopydata( "$id\n" ); };
        die( " Error on pg_putcopydata: $@" ) if ( $@ );
    }

    eval { $db->dbh->pg_putcopyend(); };
    Carp::confess( " Error on pg_putcopyend: $@" ) if ( $@ );

    $db->query( "analyze $table" );

    return $table;

}

sub begin_work
{
    my ( $self ) = @_;

    eval { $self->SUPER::begin_work; };
    if ( $@ )
    {
        Carp::confess( $@ );
    }
}

1;
