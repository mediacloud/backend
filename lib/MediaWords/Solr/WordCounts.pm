#!/usr/bin/perl -w

package MediaWords::Solr::WordCounts;

use strict;

use 5.14.0;

use Text::CSV;
use Class::CSV;
use Readonly;
use Data::Dumper;
use File::Temp qw/ tempfile tempdir /;
use Env qw(HOME);
use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Basename;

my $python_script_path;

BEGIN
{
    my $_dirname      = dirname( __FILE__ );
    my $_dirname_full = File::Spec->rel2abs( $_dirname );

    $python_script_path = "$_dirname_full/../../../python_scripts";
}

use Inline Python => "$python_script_path/solr_query_wordcount_timer.py";

my $solr;

sub word_count
{
    my ( $query, $date, $count ) = @_;

    say STDERR "starting word_count";

    if ( !defined( $solr ) )
    {
        $solr = solr_connection();
    }

    say STDERR "calling python";
    my $counts = get_word_counts( $solr, '*:*', $date, $count );

    say STDERR "returned from python";

    my $result = counts_to_db_style( $counts );

    return $result;
}

my $class_path;

BEGIN
{
    my $_dirname      = dirname( __FILE__ );
    my $_dirname_full = File::Spec->rel2abs( $_dirname );

    my $jar_dir = "$_dirname_full/jars";

    my $jars = [ 'mallet-deps.jar', 'mallet.jar' ];

    #Assumes Unix fix later.
    $class_path = scalar( join ':', ( map { "$jar_dir/$_" } @{ $jars } ) );

    #say STDERR "classpath: $class_path";
}

1;
