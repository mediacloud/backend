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
    if (
        $gearman_db->query(
            <<EOF
        SELECT 1
        FROM queue
        WHERE function_name LIKE 'MediaWords::GearmanFunction::%'
EOF
        )->hash
      )
    {
        $gearman_db->query(
            <<EOF
            UPDATE queue
            SET function_name = REPLACE(function_name, 'MediaWords::GearmanFunction::', 'MediaWords::Job::')
EOF
        );
    }
    else
    {
        say STDERR "No 'MediaWords::GearmanFunction::*' jobs to translate.";
    }

    # ::EnqueueAllControversyStories has been renamed to ::ProcessAllControversyStories
    if (
        $gearman_db->query(
            <<EOF
        SELECT 1
        FROM queue
        WHERE function_name LIKE '%::EnqueueAllControversyStories'
EOF
        )->hash
      )
    {
        $gearman_db->query(
            <<EOF
            UPDATE queue
            SET function_name = REPLACE(function_name, '::EnqueueAllControversyStories', '::ProcessAllControversyStories')
EOF
        );
    }
    else
    {
        say STDERR "No '*::EnqueueAllControversyStories' jobs to translate.";
    }

    $gearman_db->commit;
}

main();
