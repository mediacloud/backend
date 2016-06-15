#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

# This script sets all necessary postgresql environment variables based on the mediacloud configuration and then does an exec of psql
#
# For example, to connect to the default database as defined in mediawords.yml run:
#
#         ./script/run_with_carton.sh ./script/mediawords_psql_wrapper.pl
#
# This script also takes 3 special options: --db-label, --list-labels, and --dump-env_commands
#
# --db-label starts a psql client to connect to a particular database based on the label field of database section of mediawords.yml. For example, to connect to the test database run:
#      ./script/run_with_carton.sh ./script/mediawords_psql_wrapper.pl --db-label test
#
# --list-labels outputs a list of all database labels defined in mediawords.yml
#
# --dump-env_commands outputs the commands that you would use to set the relevant environment variables so that you could just run psql directly and have it connect to the given database. This is most useful for running database tools other than psql such as pg_dump and pg_restore. This option can be combined with --db-label but must be given first. For example, to get the environment variable settings for the test database run:
#
# ./script/run_with_carton.sh ./script/mediawords_psql_wrapper.pl --dump-env-commands --db-label test
#
# This will output something like the following:
#
#    export PGPASSWORD=mediacloud
#    export PGHOST=localhost
#    export PGDATABASE=mediacloud_test
#    export PGUSER=mediacloud
#
# Any arguments given after these options will be passed on to psql. So to list all Postgresql databases on a given Postgresql instance (as opposed to the databases defined in mediawords.yml) run the following:
# ./script/run_with_carton.sh ./script/mediawords_psql_wrapper.pl -l

use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::Process;

sub main
{
    my @ARGS = @ARGV;

    my $list_labels;

    my $db_label;
    my $dump_env_commands;

    if ( ( defined( $ARGS[ 0 ] ) ) && ( $ARGS[ 0 ] eq '--list-labels' ) )
    {
        $list_labels = 1;
        shift @ARGS;
    }
    else
    {
        if ( ( defined( $ARGS[ 0 ] ) ) && ( $ARGS[ 0 ] eq '--dump-env-commands' ) )
        {
            $dump_env_commands = 1;
            shift @ARGS;
        }

        if ( ( defined( $ARGS[ 0 ] ) ) && ( $ARGS[ 0 ] eq '--db-label' ) )
        {
            shift @ARGS;
            $db_label = shift @ARGS;
            die "You must specify a label if you user the db-label option" unless defined( $db_label );
        }

    }
    if ( $list_labels )
    {
        my @labels = MediaWords::DB::get_db_labels();
        foreach my $label ( @labels )
        {
            say $label;
        }
    }
    elsif ( $dump_env_commands )
    {
        MediaWords::DB::print_shell_env_commands_for_psql( $db_label );
    }
    else
    {
        MediaWords::DB::exec_psql_for_db( $db_label, @ARGS );
    }
}

main();
