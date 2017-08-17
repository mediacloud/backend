#!/usr/bin/env perl

#
# generate csvs from existings retweeter score
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use File::Slurp;
use Getopt::Long;

use MediaWords::TM;
use MediaWords::Job::GenerateRetweeterScores;

sub main
{
    my ( $retweeter_scores_id ) = @ARGV;

    die( "usage: $0 < retweeter_scores_id >" ) unless ( $retweeter_scores_id );

    my $db = MediaWords::DB::connect_to_db;

    my $score = $db->require_by_id( 'retweeter_scores', $retweeter_scores_id );

    my $media_csv = MediaWords::TM::RetweeterScores::generate_media_csv( $db, $score );
    File::Slurp::write_file( 'retweeter_media_' . $score->{ retweeter_scores_id } . '.csv', $media_csv );

    my $partition_matrix_csv = MediaWords::TM::RetweeterScores::generate_matrix_csv( $db, $score );
    File::Slurp::write_file( 'retweeter_partition_matrix_' . $score->{ retweeter_scores_id } . '.csv',
        $partition_matrix_csv );
}

main();
