package MediaWords::Job::RescrapeMedia;

#
# Search and add new feeds for media without them.
#
# FIXME some output of the job is still logged to STDOUT and not to the log:
#
#    fetch [1/1] : http://www.delfi.lt/
#    got [1/1]: http://www.delfi.lt/
#    <...>
#
# That's because MediaWords::Util::Web::UserAgent->parallel_get() starts a child process
# for fetching URLs (instead of a fork()).
#

use strict;
use warnings;

use Moose;
with 'MediaWords::JobManager::AbstractStatefulJob';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Media::Rescrape;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    my $db = MediaWords::DB::connect_to_db();

    my $media_id = $args->{ media_id };
    unless ( defined $media_id )
    {
        die "'media_id' is undefined.";
    }

    if ( $media_id == 361045 )
    {
        die "Job with media_id = 361045 manages to segfault me";
    }

    MediaWords::DBI::Media::Rescrape::rescrape_media( $db, $media_id );
}

no Moose;    # gets rid of scaffolding

1;
