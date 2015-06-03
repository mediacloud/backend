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
#    fetch [1/22] : http://www.delfi.lt/index.xml
#    got [1/22]: http://www.delfi.lt/index.xml
#    fetch [2/22] : http://www.delfi.lt/atom.xml
#    got [2/22]: http://www.delfi.lt/atom.xml
#    fetch [3/22] : http://www.delfi.lt/feeds
#    got [3/22]: http://www.delfi.lt/feeds
#    fetch [4/22] : http://www.delfi.lt/feeds/default
#    got [4/22]: http://www.delfi.lt/feeds/default
#    fetch [5/22] : http://www.delfi.lt/feed
#    got [5/22]: http://www.delfi.lt/feed
#    fetch [6/22] : http://www.delfi.lt/feed/default
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

use Modern::Perl "2013";
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

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
