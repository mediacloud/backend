package MediaWords::GearmanFunction::ExtractAndVector;

#
# Extract and vector a download
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/ExtractAndVector.pm
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
use MediaWords::DBI::Downloads;
use MediaWords::Util::GearmanJobSchedulerConfiguration;

# Having a global database object should be safe because
# Gearman::JobScheduler's workers don't support fork()s anymore
my $db = undef;

# extract + vector the download; die() and / or return false on error
sub run($$)
{
    my ( $self, $args ) = @_;

    unless ( $db )
    {
        # Postpone connecting to the database so that compile test doesn't do that
        $db = MediaWords::DB::connect_to_db();
        $db->dbh->{ AutoCommit } = 0;
    }

    my $downloads_id = $args->{ downloads_id };
    unless ( defined $downloads_id )
    {
        die "'downloads_id' is undefined.";
    }

    my $download = $db->find_by_id( 'downloads', $downloads_id );
    unless ( $download->{ downloads_id } )
    {
        die "Download with ID $downloads_id was not found.";
    }

    eval {

        my $process_id = 'gearman:' . $$;
        MediaWords::DBI::Downloads::extract_and_vector( $db, $download, $process_id );

    };
    if ( $@ )
    {

        # Probably the download was not found
        die "Extractor died: $@\n";

    }

    return 1;
}

# write a single log because there are a lot of extraction jobs so it's
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
