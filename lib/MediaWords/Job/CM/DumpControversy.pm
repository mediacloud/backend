package MediaWords::Job::CM::DumpControversy;

#
# Dump various controversy queries to csv and build a gexf file
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/Job/CM/DumpControversy.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/gjs_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::CM::Dump;
use MediaWords::DB;

# Having a global database object should be safe because
# job workers don't fork()
my $db = undef;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    unless ( $db )
    {
        # Postpone connecting to the database so that compile test doesn't do that
        $db = MediaWords::DB::connect_to_db();
    }

    my $controversies_id = $args->{ controversies_id };
    unless ( defined $controversies_id )
    {
        die "'controversies_id' is undefined.";
    }

    # No transaction started because apparently dump_controversy() does start one itself
    MediaWords::CM::Dump::dump_controversy( $db, $controversies_id );
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
