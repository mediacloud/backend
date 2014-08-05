package MediaWords::GearmanFunction::AnnotateWithCoreNLP;

#
# Process download with CoreNLP annotator HTTP service
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/AnnotateWithCoreNLP.pm
#

use strict;
use warnings;

use Moose;

# Don't log each and every extraction job into the database
with 'Gearman::JobScheduler::AbstractFunction';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/gjs_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::GearmanJobSchedulerConfiguration;

use MediaWords::Util::CoreNLP;
use MediaWords::DBI::Stories;
use Readonly;

# Having a global database object should be safe because
# Gearman::JobScheduler's workers don't support fork()s anymore
my $db = undef;

# Run CoreNLP job
sub run($;$)
{
    my ( $self, $args ) = @_;

    unless ( $db )
    {
        # Postpone connecting to the database so that compile test doesn't do that
        $db = MediaWords::DB::connect_to_db();
    }

    my $downloads_id = $args->{ downloads_id } + 0;
    unless ( $downloads_id )
    {
        die "'downloads_id' is undefined.";
    }

    $db->begin_work;

    my $download = $db->find_by_id( 'downloads', $downloads_id );
    unless ( $download->{ downloads_id } )
    {
        $db->rollback;
        die "Download with ID $downloads_id was not found.";
    }

    my $stories_id = $download->{ stories_id } + 0;

    # Annotate story with CoreNLP
    eval { MediaWords::Util::CoreNLP::store_annotation_for_story( $db, $stories_id ); };
    if ( $@ )
    {
        $db->rollback;
        die "Unable to process download $downloads_id with CoreNLP: $@\n";
    }

    # Mark the story as processed in "processed_stories" (which might contain duplicate records)
    unless ( MediaWords::DBI::Stories::mark_as_processed( $db, $stories_id ) )
    {

        # If the script wasn't able to log annotated story to PostgreSQL, this
        # is also a fatal error (meaning that the script can't continue running)
        $db->rollback;
        die 'Unable to to log annotated story $stories_id to database: ' . $db->dbh->errstr;
    }

    # Things went fine.
    $db->commit;

    return 1;
}

# write a single log because there are a lot of CoreNLP processing jobs so it's
# impractical to log each job into a separate file
sub unify_logs()
{
    return 1;
}

# (Gearman::JobScheduler::AbstractFunction implementation) Return default configuration
sub configuration()
{
    return MediaWords::Util::GearmanJobSchedulerConfiguration->instance;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
