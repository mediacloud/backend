package DBIx::Simple::MediaWords;

# local subclass of DBIx::Simple with some modification for use in media cloud code

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use base qw(DBIx::Simple);

use MediaWords::DB;
use MediaWords::Util::Config;
use MediaWords::Util::Pages;
use MediaWords::Util::SchemaVersion;

use Data::Dumper;
use DBD::Pg qw(:pg_types);
use Encode;
use File::Slurp;
use Math::Random::Secure;
use Try::Tiny;

# Environment variable which, when set, will make us ignore the schema version
Readonly my $IGNORE_SCHEMA_VERSION_ENV_VARIABLE => 'MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION';

# Min. "deadlock_timeout" to not cause problems under load (in seconds)
Readonly my $MIN_DEADLOCK_TIMEOUT => 5;

# STATICS

# cache of table primary key columns
my $_primary_key_columns = {};

# PIDs for which the schema version has been checked
my %_schema_version_check_pids;

# METHODS

sub new
{
    my $proto = shift;
    my $class = ref( $proto ) || $proto;

    my $self = $class->SUPER::new();

    bless( $self, $class );

    return $self;
}

sub connect($$$$$$;$)
{
    my ( $self, $host, $port, $user, $pass, $database, $do_not_check_schema_version ) = @_;

    unless ( $host and $user and $pass and $database )
    {
        die "Database connection credentials are not set.";
    }
    $port //= 5432;

    # If the user didn't clearly (via 'true' or 'false') state whether or not
    # to check schema version, check it once per PID
    unless ( defined $do_not_check_schema_version )
    {
        if ( $_schema_version_check_pids{ $$ } )
        {
            $do_not_check_schema_version = 1;
        }
        else
        {
            $do_not_check_schema_version = 0;
        }
    }

    my $options = {
        AutoCommit     => 1,
        pg_enable_utf8 => 1,
        RaiseError     => 1
    };

    my $dsn = "dbi:Pg:dbname=$database;host=$host;port=$port;";

    my $db = $self->SUPER::connect( $dsn, $user, $pass, $options );

    unless ( $do_not_check_schema_version )
    {

        # It would make sense to check the MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION environment variable
        # at this particular point too, but schema_is_up_to_date() warns the user about schema being
        # too old on every run, and that's supposedly a good thing.

        die "Database schema is not up-to-date." unless $db->schema_is_up_to_date();
    }

    # If schema is not up-to-date, connect() dies and we don't get to set PID here
    $_schema_version_check_pids{ $$ } = 1;

    # Check deadlock_timeout
    my $deadlock_timeout = $db->query( 'SHOW deadlock_timeout' )->flat()->[ 0 ];
    $deadlock_timeout =~ s/\s*s$//i;
    $deadlock_timeout = int( $deadlock_timeout );
    if ( $deadlock_timeout < $MIN_DEADLOCK_TIMEOUT )
    {
        WARN '"deadlock_timeout" is less than "' . $MIN_DEADLOCK_TIMEOUT . 's", expect deadlocks on high extractor load';
    }

    return $db;
}

# Schema is outdated / too new; returns 1 if MC should continue nevertheless, 0 otherwise
sub _should_continue_with_outdated_schema($$$)
{
    my ( $current_schema_version, $target_schema_version, $IGNORE_SCHEMA_VERSION_ENV_VARIABLE ) = @_;

    my $config_ignore_schema_version =
      MediaWords::Util::Config::get_config()->{ mediawords }->{ ignore_schema_version } || '';

    if ( ( $config_ignore_schema_version eq 'yes' ) || exists $ENV{ $IGNORE_SCHEMA_VERSION_ENV_VARIABLE } )
    {
        WARN <<"EOF";

The current Media Cloud database schema is older than the schema present in mediawords.sql,
but $IGNORE_SCHEMA_VERSION_ENV_VARIABLE is set so continuing anyway.
EOF
        return 1;

    }
    else
    {

        WARN <<"EOF";

################################

The current Media Cloud database schema is not the same as the schema present in mediawords.sql.

The database schema currently running in the database is $current_schema_version,
and the schema version in the mediawords.sql is $target_schema_version.

Please run:

    ./script/run_with_carton.sh ./script/mediawords_upgrade_db.pl --import

to automatically upgrade the database schema to the latest version.

If you want to connect to the Media Cloud database anyway (ignoring the schema version),
set the $IGNORE_SCHEMA_VERSION_ENV_VARIABLE environment variable as such:

    $IGNORE_SCHEMA_VERSION_ENV_VARIABLE=1 ./script/your_script.pl

################################
EOF

        return 0;
    }
}

# Checks if the database schema is up-to-date
sub schema_is_up_to_date
{
    my $self = shift @_;

    my $script_dir = MediaWords::Util::Config::get_config()->{ mediawords }->{ script_dir } || $FindBin::Bin;

    # Check if the database is empty
    my $db_vars_table_exists_query =
      "SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name='database_variables')";
    my @db_vars_table_exists = $self->query( $db_vars_table_exists_query )->flat();
    my $db_vars_table        = $db_vars_table_exists[ 0 ] + 0;
    if ( !$db_vars_table )
    {
        DEBUG "Database table 'database_variables' does not exist, probably the database is empty at this point.";
        return 1;
    }

    # Current schema version
    my $schema_version_query =
      "SELECT value AS schema_version FROM database_variables WHERE name = 'database-schema-version' LIMIT 1";
    my @schema_versions        = $self->query( $schema_version_query )->flat();
    my $current_schema_version = $schema_versions[ 0 ] + 0;
    die "Invalid current schema version.\n" unless ( $current_schema_version );

    # Target schema version
    my $sql                   = read_file( "$script_dir/mediawords.sql" );
    my $target_schema_version = MediaWords::Util::SchemaVersion::schema_version_from_lines( $sql );
    die "Invalid target schema version.\n" unless ( $target_schema_version );

    # Check if the current schema is up-to-date
    if ( $current_schema_version != $target_schema_version )
    {
        return _should_continue_with_outdated_schema( $current_schema_version, $target_schema_version,
            $IGNORE_SCHEMA_VERSION_ENV_VARIABLE );
    }
    else
    {

        # Things are fine at this point.
        return 1;
    }

}

{
    # Wrapper around query result
    #
    # Clarifies which DBIx::Simple helpers are being used and need to be ported
    # to Python)
    package DBIx::Simple::MediaWords::Result;

    use strict;
    use warnings;

    use Data::Dumper;

    sub new
    {
        my $class      = shift;
        my $db         = shift;
        my @query_args = @_;

        if ( ref( $db ) ne 'DBIx::Simple::MediaWords' )
        {
            die "Database is not a reference to DBIx::Simple::MediaWords but rather to " . ref( $db );
        }

        if ( scalar( @query_args ) == 0 )
        {
            die 'No query or its parameters.';
        }
        unless ( $query_args[ 0 ] )
        {
            die 'Query is empty or undefined.';
        }

        my $self = {};
        bless $self, $class;

        eval { $self->{ result } = $db->_query_super( @query_args ); };
        if ( $@ )
        {
            die "Query error: $@";
        }

        return $self;
    }

    #
    # DBIx::Simple::Result methods
    #

    # Returns a list of column names
    sub columns($)
    {
        my $self = shift;
        return $self->{ result }->columns;
    }

    # Returns the number of rows affected by the last row affecting command,
    # or -1 if the number of rows is not known or not available
    sub rows($)
    {
        my $self = shift;
        return $self->{ result }->rows;
    }

    # bind(LIST) -- not used
    # attr(...) -- not used
    # func(...) -- not used
    # finish -- not used

    #
    # Fetching a single row at a time
    #

    # Returns a reference to an array
    sub array($)
    {
        my $self = shift;
        return $self->{ result }->array;
    }

    # Returns a reference to a hash, keyed by column name
    sub hash($)
    {
        my $self = shift;
        return $self->{ result }->hash;
    }

    # fetch -- not used
    # into(LIST) -- not used
    # kv_list -- not used
    # kv_array -- not used

    #
    # Fetching all remaining rows
    #

    # Returns a flattened list
    sub flat($)
    {
        my $self = shift;
        return $self->{ result }->flat;
    }

    # Returns a list of references to hashes, keyed by column name
    sub hashes($)
    {
        my $self = shift;
        return $self->{ result }->hashes;
    }

    # Returns a string with a simple text representation of the data. $type can
    # be any of: neat, table, box. It defaults to table if Text::Table is
    # installed, to neat if it isn't
    sub text($$)
    {
        my ( $self, $type ) = @_;
        return $self->{ result }->text( $type );
    }

    # arrays -- not used
    # kv_flat -- not used
    # kv_arrays -- not used
    # objects($class, ...) -- not used
    # map_arrays($column_number) -- not used
    # map_hashes($column_name) -- not used
    # map -- not used
    # xto(%attr) -- not used
    # html(%attr) -- not used

    1;
}

sub _query_super
{
    my $self       = shift;
    my @query_args = @_;

    # Calls DBIx::Simple directly
    $self->SUPER::query( @query_args );
}

sub query
{
    my $self       = shift;
    my @query_args = @_;

    return DBIx::Simple::MediaWords::Result->new( $self, @query_args );
}

sub _get_current_work_mem
{
    my $self = shift @_;

    my ( $ret ) = $self->query( "SHOW work_mem" )->flat();

    return $ret;
}

sub _get_large_work_mem
{
    my $self = shift @_;

    my $config = MediaWords::Util::Config::get_config;

    my $ret = $config->{ mediawords }->{ large_work_mem };

    if ( !defined( $ret ) )
    {
        $ret = $self->_get_current_work_mem();
    }

    return $ret;
}

sub _set_work_mem
{
    my ( $self, $new_work_mem ) = @_;

    $self->query( "SET work_mem = ? ", $new_work_mem );

    return;
}

sub run_block_with_large_work_mem($&)
{
    my ( $self, $block ) = @_;

    unless ( $block and ref( $block ) eq 'CODE' )
    {
        LOGCONFESS "Block is undefined or is not a subref.";
    }
    unless ( $self and ref( $self ) eq 'DBIx::Simple::MediaWords' )
    {
        LOGCONFESS "Database handler is undefined or is not a database instance.";
    }

    TRACE "starting run_block_with_large_work_mem";

    my $large_work_mem = $self->_get_large_work_mem();

    my $old_work_mem = $self->_get_current_work_mem();

    $self->_set_work_mem( $large_work_mem );

    try
    {
        $block->( $self );
    }
    catch
    {
        $self->_set_work_mem( $old_work_mem );

        LOGCONFESS $_;
    };

    $self->_set_work_mem( $old_work_mem );

    TRACE "exiting run_block_with_large_work_mem";
}

sub execute_with_large_work_mem
{
    my $self = shift @_;

    if ( scalar( @_ ) == 0 )
    {
        LOGCONFESS 'No query or its parameters.';
    }
    unless ( $_[ 0 ] )
    {
        LOGCONFESS 'Query is empty or undefined.';
    }

    my @args = @_;
    $self->run_block_with_large_work_mem(
        sub {
            $self->query( @args );
        }
    );
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

    LOGCONFESS "undefined primary key column for table '$table'" unless defined( $id_col );

    return $self->query( "select * from $table where $id_col = ?", $id )->hash;
}

# find_by_id or die if not found
sub require_by_id
{
    my ( $self, $table, $id ) = @_;

    my $row = $self->find_by_id( $table, $id );

    die( "Unable to find id '$id' in table '$table'" ) unless ( $row );

    return $row;
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

    $self->update( $table, $hash, { $id_col => $id } );

    while ( my ( $k, $v ) = each( %{ $hidden_values } ) )
    {
        $hash->{ $k } = $v;
    }

    my $r = $self->query( "select * from $table where $id_col = \$1", $id )->hash;

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

                    # INFO "Field '$field_name' was changed from: " . $old_hash->{$field_name} .
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
        DEBUG "Nothing to do.";
        return 1;
    }

    # Start transaction
    $self->begin_work;

    # Make the change
    my $r = 0;
    eval { $r = $self->update_by_id( $table, $id, $new_hash ); };
    if ( $@ )
    {

        # Update failed
        $self->rollback;
        die $@;
    }

    require MediaWords::DBI::Activities;

    # Update succeeded, write the activity log
    unless ( MediaWords::DBI::Activities::log_activities( $self, $activity_name, $username, $id, $reason, \@changes ) )
    {
        $self->rollback;
        die "Logging one of the changes failed: $@";
    }

    # Things went fine at this point, commit
    $self->commit;

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

        LOGCONFESS "error inserting into table '$table' with object:\n" . Dumper( $hash ) . "\n$query_error";
    }

    my $id;

    eval {
        $id = $self->last_insert_id( undef, undef, $table, undef );

        LOGCONFESS "Could not get last id inserted" if ( !defined( $id ) );
    };

    LOGCONFESS "Error getting last_insert_id $@" if ( $@ );

    my $ret = $self->find_by_id( $table, $id );

    LOGCONFESS "could not find new id '$id' in table '$table' " unless ( $ret );

    return $ret;
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
    my ( $self, $query, $page, $rows_per_page ) = @_;

    if ( $page < 1 )
    {
        die 'Page must be 1 or bigger.';
    }

    my $offset = ( $page - 1 ) * $rows_per_page;

    $query .= " limit ( $rows_per_page + 1 ) offset $offset";

    my $rs = $self->query( $query );

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

    my $pager = MediaWords::Util::Pages->new( $max, $rows_per_page, $page );

    return ( $list, $pager );

}

# for each row in $data, attach all results in the child query that match a join with the $id_column field in each
# row of $data.  attach to $row->{ $child_field } the $child_field column in the corresponding row in $data.
sub attach_child_query_singleton ($$$$$)
{
    my ( $self, $data, $child_query, $child_field, $id_column ) = @_;

    my $ids_table = $self->get_temporary_ids_table( [ map { $_->{ $id_column } } @{ $data } ] );

    my $children = $self->query( <<SQL )->hashes;
select q.* from ( $child_query ) q join $ids_table ids on ( q.$id_column = ids.id )
SQL

    my $parent_lookup = {};

    for my $parent ( @{ $data } )
    {
        $parent_lookup->{ $parent->{ $id_column } } = $parent;
    }

    for my $child ( @{ $children } )
    {
        my $parent = $parent_lookup->{ $child->{ $id_column } };

        $parent->{ $child_field } = $child->{ $child_field };
    }

    return $data;
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

# get the name of a temporary table that contains all of the ids in $ids as an 'id bigint' field.
# the database connection must be within a transaction.  the temporary table is setup to be dropped
# at the end of the current transaction. row insertion order is maintained.
# if $ordered is true, include an ${ids_table}_id serial primary key field in the table.
sub get_temporary_ids_table($;$$)
{
    my ( $self, $ids, $ordered ) = @_;

    my $table = "_tmp_ids_" . Math::Random::Secure::irand( 2**64 );
    TRACE( "temporary ids table: $table" );

    my $pk = $ordered ? " ${table}_pkey   SERIAL  PRIMARY KEY," : "";

    $self->query( "create temporary table $table ( $pk id bigint )" );

    $self->dbh->do( "COPY $table (id) FROM STDIN" );

    for my $id ( @{ $ids } )
    {
        $self->dbh->pg_putcopydata( "$id\n" );
    }

    $self->dbh->pg_putcopyend();

    $self->query( "ANALYZE $table" );

    return $table;
}

sub begin_work
{
    my ( $self ) = @_;

    eval { $self->SUPER::begin_work; };
    if ( $@ )
    {
        LOGCONFESS( $@ );
    }
}

# Alias for DBD::Pg's quote()
sub quote($$)
{
    my ( $self, $value ) = @_;
    return $self->dbh->quote( $value );
}

sub quote_bool($$)
{
    my ( $self, $value ) = @_;
    return $self->dbh->quote( $value, { pg_type => DBD::Pg::PG_BOOL } );
}

sub quote_varchar($$)
{
    my ( $self, $value ) = @_;
    return $self->dbh->quote( $value, { pg_type => DBD::Pg::PG_VARCHAR } );
}

sub quote_date($$)
{
    my ( $self, $value ) = @_;
    return $self->dbh->quote( $value, { pg_type => DBD::Pg::PG_VARCHAR } ) . '::date';
}

sub quote_timestamp($$)
{
    my ( $self, $value ) = @_;
    return $self->dbh->quote( $value, { pg_type => DBD::Pg::PG_VARCHAR } ) . '::timestamp';
}

{
    # Wrapper around prepared statement
    package DBIx::Simple::MediaWords::Statement;

    use strict;
    use warnings;

    use DBD::Pg qw(:pg_types);

    our $VALUE_BYTEA = 1;

    # There are other types (e.g. PG_POINT), but they aren't used currently by
    # any live code

    sub new($$$)
    {
        my ( $class, $db, $sql ) = @_;

        my $self = {};
        bless $self, $class;

        $self->{ db }  = $db;
        $self->{ sql } = $sql;

        eval { $self->{ sth } = $db->dbh->prepare( $sql ); };
        if ( $@ )
        {
            die "Error while preparing statement '$sql': $@";
        }

        return $self;
    }

    sub bind_param($$$;$)
    {
        my ( $self, $param_num, $bind_value, $bind_type ) = @_;

        if ( $param_num < 1 )
        {
            die "Parameter number must be >= 1.";
        }

        my $bind_args = undef;
        if ( defined $bind_type )
        {
            if ( $bind_type == $VALUE_BYTEA )
            {
                $bind_args = { pg_type => DBD::Pg::PG_BYTEA };
            }
            else
            {
                die "Unknown bind type $bind_type.";
            }
        }

        eval { $self->{ sth }->bind_param( $param_num, $bind_value, $bind_args ); };
        if ( $@ )
        {
            die "Error while binding parameter $param_num for prepared statement '" . $self->{ sql } . "': $@";
        }
    }

    sub execute($)
    {
        my ( $self ) = @_;

        eval { $self->{ sth }->execute(); };
        if ( $@ )
        {
            die "Error while executing prepared statement '" . $self->{ sql } . "': $@";
        }
    }

    1;
}

# Alias for DBD::Pg's prepare()
sub prepare($$)
{
    my ( $self, $sql ) = @_;

    # Tiny wrapper around DBD::Pg's statement
    return DBIx::Simple::MediaWords::Statement->new( $self, $sql );
}

# for each row in $data, attach all results in the child query that match a join with the $id_column field in each
# row of $data.  attach to $row->{ $child_field } an array of values for each row in $data
sub attach_child_query($$$$$)
{
    my ( $self, $data, $child_query, $child_field, $id_column ) = @_;

    my $ids_table = $self->get_temporary_ids_table( [ map { $_->{ $id_column } } @{ $data } ] );

    my $children = $self->query( <<SQL )->hashes;
select q.* from ( $child_query ) q join $ids_table ids on ( q.$id_column = ids.id )
SQL

    my $parent_lookup = {};

    for my $parent ( @{ $data } )
    {
        $parent_lookup->{ $parent->{ $id_column } } = $parent;
        $parent->{ $child_field } = [];
    }

    for my $child ( @{ $children } )
    {
        my $parent = $parent_lookup->{ $child->{ $id_column } };
        push( @{ $parent->{ $child_field } }, $child );
    }

    return $data;
}

sub autocommit($)
{
    my $self = shift;
    return $self->{ dbh }->{ AutoCommit };
}

sub set_autocommit($$)
{
    my ( $self, $autocommit ) = @_;
    $self->{ dbh }->{ AutoCommit } = $autocommit;
}

sub show_error_statement($)
{
    my $self = shift;
    return $self->{ dbh }->{ ShowErrorStatement };
}

sub set_show_error_statement($$)
{
    my ( $self, $show_error_statement ) = @_;
    $self->{ dbh }->{ ShowErrorStatement } = $show_error_statement;
}

sub print_warn($)
{
    my $self = shift;
    return $self->{ dbh }->{ PrintWarn };
}

sub set_print_warn($$)
{
    my ( $self, $print_warn ) = @_;
    $self->{ dbh }->{ PrintWarn } = $print_warn;
}

sub prepare_on_server_side($)
{
    my $self = shift;
    return $self->dbh->{ pg_server_prepare };
}

sub set_prepare_on_server_side($$)
{
    my ( $self, $prepare_on_server_side ) = @_;
    $self->dbh->{ pg_server_prepare } = $prepare_on_server_side;
}

# COPY FROM helpers
sub copy_from_start($$)
{
    my ( $self, $sql ) = @_;

    eval { $self->dbh->do( $sql ) };
    if ( $@ )
    {
        die "Error while running '$sql': $@";
    }
}

sub copy_from_put_line($$)
{
    my ( $self, $line ) = @_;

    chomp $line;

    eval { $self->dbh->pg_putcopydata( "$line\n" ); };
    if ( $@ )
    {
        die "Error on pg_putcopydata('$line'): $@";
    }
}

sub copy_from_end($)
{
    my ( $self ) = @_;

    eval { $self->dbh->pg_putcopyend(); };
    if ( $@ )
    {
        die "Error on pg_putcopyend(): $@";
    }
}

# COPY TO helpers
sub copy_to_start($$)
{
    my ( $self, $sql ) = @_;

    eval { $self->dbh->do( $sql ) };
    if ( $@ )
    {
        die "Error while running '$sql': $@";
    }
}

sub copy_to_get_line($)
{
    my ( $self ) = @_;

    my $line = '';
    if ( $self->dbh->pg_getcopydata( $line ) > -1 )
    {
        return $line;
    }
    else
    {
        return undef;
    }
}

1;
