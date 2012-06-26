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

    if ( $ARGS[0] eq '--list-labels' )
    {
	$list_labels = 1;
	shift @ARGS;
    }
    elsif ( $ARGS[0] eq '--db-label' )
    {
	shift @ARGS;
	$db_label = shift @ARGS;
	die "You must specify a label if you user the db-label option" unless defined( $db_label );
    }

    if ( $list_labels )
    {
	## TODO
    }
    else
    {
	MediaWords::DB::exec_psql_for_db( $db_label, @ARGS);
    }
}

main();
