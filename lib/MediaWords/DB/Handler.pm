package MediaWords::DB::Handler;

# Database handler: proxy package to DBIx::Simple with some extra helpers

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB::Handler::CopyFrom;
use MediaWords::DB::Handler::CopyTo;
use MediaWords::DB::Handler::Result;
use MediaWords::DB::Handler::Statement;
use MediaWords::DB::Schema::Version;
use MediaWords::DB;
use MediaWords::Util::Config;
use MediaWords::Util::Pages;
use MediaWords::Util::Paths;

use Data::Dumper;
use DBD::Pg qw(:pg_types);
use DBIx::Simple;
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
    my $class = shift;
    return $class->connect( @_ );
}

# Constructor
sub connect($$$$$$;$)
{
    my $class = shift;
    my ( $host, $port, $user, $pass, $database, $do_not_check_schema_version ) = @_;

    my $self = {};
    bless $self, $class;

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
        pg_enable_utf8 => 1,
        RaiseError     => 1
    };

    my $dsn = "dbi:Pg:dbname=$database;host=$host;port=$port;";

    eval { $self->{ _db } = DBIx::Simple->connect( $dsn, $user, $pass, $options ); };
    if ( $@ )
    {
        die "Unable to connect to DSN $dsn: " . DBIx::Simple->error;
    }

    $self->autocommit( 1 );

    unless ( $do_not_check_schema_version )
    {

        # It would make sense to check the MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION environment variable
        # at this particular point too, but schema_is_up_to_date() warns the user about schema being
        # too old on every run, and that's supposedly a good thing.

        die "Database schema is not up-to-date." unless $self->schema_is_up_to_date();
    }

    # If schema is not up-to-date, connect() dies and we don't get to set PID here
    $_schema_version_check_pids{ $$ } = 1;

    # Check deadlock_timeout
    my $deadlock_timeout = $self->query( 'SHOW deadlock_timeout' )->flat()->[ 0 ];
    $deadlock_timeout =~ s/\s*s$//i;
    $deadlock_timeout = int( $deadlock_timeout );
    if ( $deadlock_timeout < $MIN_DEADLOCK_TIMEOUT )
    {
        WARN '"deadlock_timeout" is less than "' . $MIN_DEADLOCK_TIMEOUT . 's", expect deadlocks on high extractor load';
    }

    return $self;
}

sub disconnect
{
    my ( $self ) = @_;

    $self->{ _db }->disconnect;
    delete $self->{ _db };
}

sub dbh
{
    LOGCONFESS "Please don't use internal 'dbh' handle anymore; instead, use one of MediaWords::DB::Handler helpers.";
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
    my $root_path             = MediaWords::Util::Paths::mc_root_path();
    my $sql                   = read_file( "$root_path/schema/mediawords.sql" );
    my $target_schema_version = MediaWords::DB::Schema::Version::schema_version_from_lines( $sql );
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

sub _query_internal
{
    my $self       = shift;
    my @query_args = @_;

    # Calls DBIx::Simple directly
    $self->{ _db }->query( @query_args );
}

sub query
{
    my $self       = shift;
    my @query_args = @_;

    return MediaWords::DB::Handler::Result->new( $self, @query_args );
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

# Run an argument subroutine block with large "work_mem" enabled
#
# This helper DOES NOT return a result (due to internals of psycopg2), so make
# sure to store whatever you want to store within an argument subroutine.
sub run_block_with_large_work_mem($&)
{
    my ( $self, $block ) = @_;

    unless ( $block and ref( $block ) eq 'CODE' )
    {
        LOGCONFESS "Block is undefined or is not a subref.";
    }
    unless ( $self and ref( $self ) eq 'MediaWords::DB::Handler' )
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

# Execute an argument query with large "work_mem" enabled
#
# This helper DOES NOT return a result (due to internals of psycopg2). If you
# need a result, either:
#
# 1) use run_block_with_large_work_mem() and store the result in a variable
#    within a subroutine, or
# 2) store it in a temporary table and fetch it afterwards.
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

    my ( $id_col ) = $self->{ _db }->dbh->primary_key( undef, undef, $table );

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

sub select($)
{
    my ( $self, $table, $what_to_select, $condition_hash ) = @_;

    return $self->{ _db }->select( $table, $what_to_select, $condition_hash );
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

    $self->{ _db }->update( $table, $hash, { $id_col => $id } );

    while ( my ( $k, $v ) = each( %{ $hidden_values } ) )
    {
        $hash->{ $k } = $v;
    }

    my $r = $self->query( "select * from $table where $id_col = \$1", $id )->hash;

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
sub insert
{
    my ( $self, $table, $hash ) = @_;

    delete( $hash->{ submit } );

    eval { $self->{ _db }->insert( $table, $hash ); };

    if ( $@ )
    {
        my $query_error = $@;

        LOGCONFESS "error inserting into table '$table' with object:\n" . Dumper( $hash ) . "\n$query_error";
    }

    my $id;

    eval {
        $id = $self->{ _db }->last_insert_id( undef, undef, $table, undef );

        LOGCONFESS "Could not get last id inserted" if ( !defined( $id ) );
    };

    LOGCONFESS "Error getting last_insert_id $@" if ( $@ );

    my $ret = $self->find_by_id( $table, $id );

    LOGCONFESS "could not find new id '$id' in table '$table' " unless ( $ret );

    return $ret;
}

# alias to insert()
sub create
{
    my ( $self, $table, $hash ) = @_;

    return $self->insert( $table, $hash );
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

# get the name of a temporary table that contains all of the ids in $ids as an 'id bigint' field.
# the database connection must be within a transaction.  the temporary table is setup to be dropped
# at the end of the current transaction. row insertion order is maintained.
# if $ordered is true, include an ${ids_table}_id serial primary key field in the table.
sub get_temporary_ids_table($$;$)
{
    my ( $self, $ids, $ordered ) = @_;

    my $table = "_tmp_ids_" . Math::Random::Secure::irand( 2**64 );
    TRACE( "temporary ids table: $table" );

    my $pk = $ordered ? " ${table}_pkey   SERIAL  PRIMARY KEY," : "";

    $self->query( "create temporary table $table ( $pk id bigint )" );

    $self->{ _db }->dbh->do( "COPY $table (id) FROM STDIN" );

    for my $id ( @{ $ids } )
    {
        $self->{ _db }->dbh->pg_putcopydata( "$id\n" );
    }

    $self->{ _db }->dbh->pg_putcopyend();

    $self->query( "ANALYZE $table" );

    return $table;
}

sub begin
{
    my ( $self ) = @_;

    return $self->begin_work;
}

sub begin_work
{
    my ( $self ) = @_;

    $self->{ _db }->begin_work;
}

sub commit
{
    my ( $self ) = @_;

    return $self->{ _db }->commit;
}

sub rollback
{
    my ( $self ) = @_;

    return $self->{ _db }->rollback;
}

# Alias for DBD::Pg's quote()
sub quote($$)
{
    my ( $self, $value ) = @_;
    return $self->{ _db }->dbh->quote( $value );
}

sub quote_bool($$)
{
    my ( $self, $value ) = @_;
    return $self->{ _db }->dbh->quote( $value, { pg_type => DBD::Pg::PG_BOOL } );
}

sub quote_varchar($$)
{
    my ( $self, $value ) = @_;
    return $self->{ _db }->dbh->quote( $value, { pg_type => DBD::Pg::PG_VARCHAR } );
}

sub quote_date($$)
{
    my ( $self, $value ) = @_;
    return $self->{ _db }->dbh->quote( $value, { pg_type => DBD::Pg::PG_VARCHAR } ) . '::date';
}

sub quote_timestamp($$)
{
    my ( $self, $value ) = @_;
    return $self->{ _db }->dbh->quote( $value, { pg_type => DBD::Pg::PG_VARCHAR } ) . '::timestamp';
}

# Alias for DBD::Pg's prepare()
sub prepare($$)
{
    my ( $self, $sql ) = @_;

    # Tiny wrapper around DBD::Pg's statement
    return MediaWords::DB::Handler::Statement->new( $self, $sql );
}

sub autocommit($)
{
    my $self = shift;
    return $self->{ _db }->dbh->{ AutoCommit };
}

sub set_autocommit($$)
{
    my ( $self, $autocommit ) = @_;
    $self->{ _db }->dbh->{ AutoCommit } = $autocommit;
}

sub show_error_statement($)
{
    my $self = shift;
    return $self->{ _db }->dbh->{ ShowErrorStatement };
}

sub set_show_error_statement($$)
{
    my ( $self, $show_error_statement ) = @_;
    $self->{ _db }->dbh->{ ShowErrorStatement } = $show_error_statement;
}

sub print_warn($)
{
    my $self = shift;
    return $self->{ _db }->dbh->{ PrintWarn };
}

sub set_print_warn($$)
{
    my ( $self, $print_warn ) = @_;
    $self->{ _db }->dbh->{ PrintWarn } = $print_warn;
}

sub prepare_on_server_side($)
{
    my $self = shift;
    return $self->{ _db }->dbh->{ pg_server_prepare };
}

sub set_prepare_on_server_side($$)
{
    my ( $self, $prepare_on_server_side ) = @_;
    $self->{ _db }->dbh->{ pg_server_prepare } = $prepare_on_server_side;
}

sub copy_from($$)
{
    my ( $self, $sql ) = @_;

    return MediaWords::DB::Handler::CopyFrom->new( $self, $sql );
}

sub copy_to($$)
{
    my ( $self, $sql ) = @_;

    return MediaWords::DB::Handler::CopyTo->new( $self, $sql );
}

# For each row in $data, attach all results in the child query that match a
# join with the $id_column field in each row of $data.
#
# Then, attach to $row->{ $child_field }:
#
# * If $single is true, the $child_field column in the corresponding row in
#   $data:
#
#        CREATE TEMPORARY TABLE names (
#            id INT NOT NULL,
#            name VARCHAR NOT NULL
#        );
#        INSERT INTO names (id, name)
#        VALUES (1, 'John'), (2, 'Jane'), (3, 'Joe');
#
#        my $surnames = [
#            { 'id' => 1, 'surname' => 'Doe' },
#            { 'id' => 2, 'surname' => 'Roe' },
#            { 'id' => 3, 'surname' => 'Bloggs' },
#        ];
#
#        my $child_query = 'SELECT id, name FROM names';
#        my $child_field = 'name';
#        my $id_column = 'id';
#        my $single = 1;
#
#        print( Dumper( $db->attach_child_query(
#            $names,
#            $child_query,
#            $child_field,
#            $id_column,
#            $single
#        ));
#
#            # [
#            #     {
#            #         'id' => 1,
#            #         'name' => 'John',
#            #         'surname' => 'Doe'
#            #     },
#            #     {
#            #         'id' => 2,
#            #         'name' => 'Jane',
#            #         'surname' => 'Roe'
#            #     },
#            #     {
#            #         'id' => 3,
#            #         'name' => 'Joe',
#            #         'surname' => 'Bloggs'
#            #     }
#            # ];
#
#
# * If $single is false, an array of values for each row in $data:
#
#        CREATE TEMPORARY TABLE dogs (
#            owner_id INT NOT NULL,
#            dog_name VARCHAR NOT NULL
#        );
#        INSERT INTO dogs (owner_id, dog_name)
#        VALUES (1, 'Bailey'), (1, 'Max'), (2, 'Charlie'), (2, 'Bella'), (3, 'Lucy'), (3, 'Molly');
#
#        my $owners = [
#            { 'owner_id' => 1, 'owner_name' => 'John' },
#            { 'owner_id' => 2, 'owner_name' => 'Jane' },
#            { 'owner_id' => 3, 'owner_name' => 'Joe' },
#        ];
#
#        my $child_query = 'SELECT owner_id, dog_name FROM dogs';
#        my $child_field = 'owned_dogs';
#        my $id_column = 'owner_id';
#        my $single = 0;
#
#        print( Dumper( $db->attach_child_query(
#            $owners,
#            $child_query,
#            $child_field,
#            $id_column,
#            $single
#        ));
#
#            # [
#            #     {
#            #         'owner_id' => 1,
#            #         'owner_name' => 'John',
#            #         'owned_dogs' => [
#            #             {
#            #                 'dog_name' => 'Bailey',
#            #                 'owner_id' => 1
#            #             },
#            #             {
#            #                 'owner_id' => 1,
#            #                 'dog_name' => 'Max'
#            #             }
#            #         ]
#            #     },
#            #     {
#            #         'owner_id' => 2,
#            #         'owner_name' => 'Jane',
#            #         'owned_dogs' => [
#            #             {
#            #                 'owner_id' => 2,
#            #                 'dog_name' => 'Charlie'
#            #             },
#            #             {
#            #                 'dog_name' => 'Bella',
#            #                 'owner_id' => 2
#            #             }
#            #         ]
#            #     },
#            #     {
#            #         'owner_id' => 3,
#            #         'owner_name' => 'Joe',
#            #         'owned_dogs' => [
#            #             {
#            #                 'dog_name' => 'Lucy',
#            #                 'owner_id' => 3
#            #             },
#            #             {
#            #                 'owner_id' => 3,
#            #                 'dog_name' => 'Molly'
#            #             }
#            #         ]
#            #     }
#            # ];
#
#
# FIXME get rid of this hard to understand reimplementation of JOIN which is
# here due to the sole reason that _add_nested_data() is hard to refactor out.
#
sub attach_child_query($$$$$;$)
{
    my ( $self, $data, $child_query, $child_field, $id_column, $single ) = @_;

    my $parent_lookup = {};
    my $ids           = [];
    for my $parent ( @{ $data } )
    {
        my $parent_id = $parent->{ $id_column };

        $parent_lookup->{ $parent_id } = $parent;
        push( @{ $ids }, $parent_id );
    }

    my $ids_table = $self->get_temporary_ids_table( $ids );
    my $children  = $self->query(
        <<"SQL"
        SELECT q.*
        FROM ( $child_query ) AS q
            -- Limit rows returned by $child_query to only IDs from $ids
            INNER JOIN $ids_table AS ids ON q.$id_column = ids.id
SQL
    )->hashes;

    for my $child ( @{ $children } )
    {
        my $child_id = $child->{ $id_column };

        my $parent = $parent_lookup->{ $child_id };

        if ( $single )
        {
            $parent->{ $child_field } = $child->{ $child_field };
        }
        else
        {
            $parent->{ $child_field } //= [];
            push( @{ $parent->{ $child_field } }, $child );
        }
    }

    return $data;
}

1;
