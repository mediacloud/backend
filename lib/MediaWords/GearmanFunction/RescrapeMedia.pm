package MediaWords::GearmanFunction::RescrapeMedia;

#
# Search and add new feeds for unmoderated media (media sources that have not
# had default feeds added to them).
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/RescrapeMedia.pm
#
# FIXME some output of the job is still logged to STDOUT and not to the log:
#
#    fetch [1/1] : http://www.delfi.lt/
#    got [1/1]: http://www.delfi.lt/
#    <...>
#
# That's because MediaWords::Util::Web::ParallelGet() starts a child process
# for fetching URLs (instead of a fork()).
#

use strict;
use warnings;

use Moose;
with 'MediaWords::GearmanFunction';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/gjs_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Media::Rescrape;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    my $media_id = $args->{ media_id };
    unless ( defined $media_id )
    {
        die "'media_id' is undefined.";
    }

    my $db = MediaWords::DB::connect_to_db();

    MediaWords::DBI::Media::Rescrape::rescrape_media( $db, $media_id );
}

# write a single log instead of many separate logs
sub unify_logs()
{
    return 1;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
