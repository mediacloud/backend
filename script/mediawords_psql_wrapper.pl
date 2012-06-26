#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::MC_Fork;

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
