package MediaWords::Pg::Schema;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::Languages::Language;

# import functions into server schema

use strict;
use warnings;

use IPC::Run3;
use Carp;
use FindBin;

# to add a new function to the db
# * write the function in a new or existing MediaWords::Pg module
# * add the module, function, number of parameters, and return_type to $_functions
# * run add_functions to reload all functions

my $_functions = [

    # [ module name, function name, number of parameters, return_type ]
    [ 'MediaWords::Pg::Cleanup', 'remove_duplicate_stories', 2, 'text' ],
    [ 'MediaWords::Util::HTML',  'html_strip',               1, 'text' ],
];

my $_spi_functions = [
    qw/spi_exec_query spi_query spi_fetchrow spi_prepare spi_exec_prepared
      spi_query_prepared spi_cursor_close spi_freeplan elog/
];
my $_spi_constants = [ qw/DEBUG LOG INFO NOTICE WARNING ERROR/ ];

# get is_stop_stem() stopword + stopword stem tables and a pl/pgsql function definition
sub get_is_stop_stem_function_tables_and_definition
{
    my $sql = '';

    my $lang = MediaWords::Languages::Language::lang();

    my @stoplist_sizes = ( 'tiny', 'short', 'long' );

    for my $stoplist_size ( @stoplist_sizes )
    {

        # create tables
        $sql .= <<END

            -- PostgreSQL sends notices about implicit keys that are being created,
            -- and the test suite takes them for warnings.
            SET client_min_messages=WARNING;

            -- "Full" stopwords
            DROP TABLE IF EXISTS stopwords_${stoplist_size};
            CREATE TABLE stopwords_${stoplist_size} (
                stopwords_id SERIAL PRIMARY KEY,
                stopword VARCHAR(256) NOT NULL
            ) WITH (OIDS=FALSE);
            CREATE UNIQUE INDEX stopwords_${stoplist_size}_stopword ON stopwords_${stoplist_size}(stopword);

            -- Stopword stems
            DROP TABLE IF EXISTS stopword_stems_${stoplist_size};
            CREATE TABLE stopword_stems_${stoplist_size} (
                stopword_stems_id SERIAL PRIMARY KEY,
                stopword_stem VARCHAR(256) NOT NULL
            ) WITH (OIDS=FALSE);
            CREATE UNIQUE INDEX stopword_stems_${stoplist_size}_stopword_stem ON stopword_stems_${stoplist_size}(stopword_stem);

            -- Reset the message level back to "notice".
            SET client_min_messages=NOTICE;

END
          ;

        # collect stopwords
        my $stopwords_hashref;
        if ( $stoplist_size eq 'tiny' )
        {
            $stopwords_hashref = $lang->get_tiny_stop_words();
        }
        elsif ( $stoplist_size eq 'short' )
        {
            $stopwords_hashref = $lang->get_short_stop_words();
        }
        elsif ( $stoplist_size eq 'long' )
        {
            $stopwords_hashref = $lang->get_long_stop_words();
        }
        my @stopwords;
        while ( my ( $stopword, $value ) = each %{ $stopwords_hashref } )
        {
            if ( $value == 1 )
            {
                $stopword =~ s/'/''/;
                push( @stopwords, "('$stopword')" );
            }
        }

        # collect stopword stems
        my $stopword_stems_hashref;
        if ( $stoplist_size eq 'tiny' )
        {
            $stopword_stems_hashref = $lang->get_tiny_stop_word_stems();
        }
        elsif ( $stoplist_size eq 'short' )
        {
            $stopword_stems_hashref = $lang->get_short_stop_word_stems();
        }
        elsif ( $stoplist_size eq 'long' )
        {
            $stopword_stems_hashref = $lang->get_long_stop_word_stems();
        }
        my @stopword_stems;
        while ( my ( $stopword_stem, $value ) = each %{ $stopword_stems_hashref } )
        {
            if ( $value == 1 )
            {
                $stopword_stem =~ s/'/''/;
                push( @stopword_stems, "('$stopword_stem')" );
            }
        }

        # insert stopwords and stopword stems
        $sql .= 'INSERT INTO stopwords_' . $stoplist_size . ' (stopword) VALUES ' . join( ', ', @stopwords ) . ';';
        $sql .=
          'INSERT INTO stopword_stems_' . $stoplist_size . ' (stopword_stem) VALUES ' . join( ', ', @stopword_stems ) . ';';
    }

    # create a function
    $sql .= <<END

        CREATE OR REPLACE FUNCTION is_stop_stem(size TEXT, stem TEXT)
            RETURNS BOOLEAN AS \$\$
        DECLARE
            result BOOLEAN;
        BEGIN

            -- Tiny
            IF size = 'tiny' THEN
                SELECT 't' INTO result FROM stopword_stems_tiny WHERE stopword_stem = stem;
                IF NOT FOUND THEN
                    result := 'f';
                END IF;

            -- Short
            ELSIF size = 'short' THEN
                SELECT 't' INTO result FROM stopword_stems_short WHERE stopword_stem = stem;
                IF NOT FOUND THEN
                    result := 'f';
                END IF;

            -- Long
            ELSIF size = 'long' THEN
                SELECT 't' INTO result FROM stopword_stems_long WHERE stopword_stem = stem;
                IF NOT FOUND THEN
                    result := 'f';
                END IF;

            -- unknown size
            ELSE
                RAISE EXCEPTION 'Unknown stopword stem size: "%" (expected "tiny", "short" or "long")', size;
                result := 'f';
            END IF;

            RETURN result;
        END;
        \$\$ LANGUAGE plpgsql;

END
      ;

    return $sql;
}

# get the sql function definitions
sub get_sql_function_definitions
{
    my $sql = '';

    for my $function ( @{ $_functions } )
    {
        my ( $module, $function_name, $num_parameters, $return_type ) = @{ $function };

        my ( $parameters, $args );
        if ( $return_type eq 'trigger' )
        {
            $parameters = '';
            $args       = '$_TD';
        }
        else
        {
            $parameters = "TEXT," x $num_parameters;
            chop( $parameters );
            $args = '@_';
        }

        my $spi_functions = join( '', map { "    MediaWords::Pg::set_spi('$_', \\&$_);\n" } @{ $_spi_functions } );
        my $spi_constants = join( '', map { "    MediaWords::Pg::set_spi('$_', $_);\n" } @{ $_spi_constants } );

        my $function_sql = <<END
create or replace function $function_name ($parameters) returns $return_type as \$\$
    use lib "$FindBin::Bin/../../";
    use lib "$FindBin::Bin/../lib";
    use MediaWords::Pg;

    \$MediaWords::Pg::in_pl_perl = 1;

    use $module;

$spi_functions
$spi_constants

    return ${module}::${function_name}($args);
\$\$ language plperlu;
END
          ;

        $sql .= "/* ${module}::${function_name}(${parameters}) */\n$function_sql\n\n";
    }

    # append is_stop_stem()
    $sql .= get_is_stop_stem_function_tables_and_definition();

    return $sql;
}

# add all of the functions defined in $_functions to the database
sub add_functions
{
    my ( $db ) = @_;

    eval { $db->query( 'create language plperlu' ); };

    my $sql = get_sql_function_definitions();
    $db->query( $sql );
}

# removes all relations belonging to a given schema
# default schema is 'public'
sub _reset_schema
{
    my ( $db, $schema ) = @_;

    $schema ||= 'public';

    # TODO: should check for failure
    {
        my $old_handler = $SIG{ __WARN__ };

        $SIG{ __WARN__ } = 'IGNORE';

        #sub {
        # say 'ignoring warning';
        #};

        no warnings;

        # By default this will complain but the drop cascading to other objects
        # THis warning is just noise so get rid of it.

        $db->dbh->trace( 0 );
        say STDERR Dumper( $db->dbh->trace );

        $db->query( "DROP SCHEMA IF EXISTS $schema CASCADE" );

        #removes schema used by dklab enum procedures
        #schema will be re-added in dklab sqlfile
        $db->query( "DROP SCHEMA IF EXISTS enum CASCADE" );

        $db->query( "DROP SCHEMA IF EXISTS stories_tags_map_media_sub_tables CASCADE" );

        $SIG{ __WARN__ } = $old_handler;
    }

    $db->query( "DROP LANGUAGE IF EXISTS plperlu CASCADE" );

    $db->query( "DROP LANGUAGE IF EXISTS plpgsql CASCADE " );
    $db->query( "CREATE LANGUAGE plpgsql" );
    $db->query( "CREATE SCHEMA $schema" );

    return undef;
}

# loads and runs a given SQL file
# useful for rebuilding the database schema after a call to reset_schema
sub load_sql_file
{
    my ( $label, $sql_file ) = @_;

    sub parse_line
    {
        my ( $line ) = @_;

        #say "Got line: '$line'";
        if ( not $line =~ /^NOTICE:|^CREATE|^ALTER|^\SET|^COMMENT|^INSERT|^psql.*: NOTICE:/ )
        {
            carp "Evil line: '$line'";
            die "Evil line: '$line'";
        }

        return $line;
    }

    my $db_settings = MediaWords::DB::connect_settings( $label );
    my $script_dir  = MediaWords::Util::Config::get_config()->{ mediawords }->{ script_dir };
    my $db_type     = $db_settings->{ type };
    my $host        = $db_settings->{ host };
    my $database    = $db_settings->{ db };
    my $username    = $db_settings->{ user };
    my $password    = $db_settings->{ pass } . "\n";

    say "$host $database $username $password ";

    # TODO: potentially brittle, $? should be checked after run3
    # common shell script interface gives indirection to database with no
    # modification of this code.
    # if there is a way to do this without popping out to a shell, please use it

    # stdout and stderr go to this script's channels. password is passed on stdin
    # so it doesn't appear in the process table
    say STDERR "loadsql: $script_dir/loadsql.$db_type.sh";
    run3( [ "$script_dir/loadsql.$db_type.sh", $sql_file, $host, $database, $username ],
        \$password, \&parse_line, \&parse_line );

    my $ret = $?;
    return $ret;
}

sub recreate_db
{
    my ( $label ) = @_;

    {
        my $db = MediaWords::DB::connect_to_db( $label );

        say STDERR "reset schema ...";
        _reset_schema( $db );

        say STDERR "add functions ...";
        MediaWords::Pg::Schema::add_functions( $db );

        $db->disconnect;
    }

    my $script_dir = MediaWords::Util::Config->get_config()->{ mediawords }->{ script_dir } || $FindBin::Bin;

    say STDERR "script_dir: $script_dir";

    say STDERR "add enum functions ...";
    my $load_dklab_postgresql_enum_result = load_sql_file( $label, "$script_dir/dklab_postgresql_enum_2009-02-26.sql" );

    die "Error adding dklab_postgresql_enum procecures" if ( $load_dklab_postgresql_enum_result );

    say STDERR "add mediacloud schema ...";
    my $load_sql_file_result = load_sql_file( $label, "$script_dir/mediawords.sql" );

    return $load_sql_file_result;
}

1;
