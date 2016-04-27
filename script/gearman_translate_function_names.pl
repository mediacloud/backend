#!/usr/bin/env perl
#
# Update queued Gearman job names after migration to MediaCloud::JobManager
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;

sub main
{
    my $gearman_db = MediaWords::DB::connect_to_db( 'gearman' );

    $gearman_db->begin_work;

    # MediaWords::GearmanFunction::* jobs have been renamed to MediaWords::Job::*
    $gearman_db->query(
        <<EOF
        UPDATE queue
        SET function_name = REPLACE(function_name, 'MediaWords::GearmanFunction::', 'MediaWords::Job::')
EOF
    );

    # ::EnqueueAllControversyStories has been renamed to ::ProcessAllControversyStories
    $gearman_db->query(
        <<EOF
        UPDATE queue
        SET function_name = REPLACE(function_name, '::EnqueueAllControversyStories', '::ProcessAllControversyStories')
EOF
    );

    $gearman_db->commit;
}

main();
