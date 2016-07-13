package MediaWords::Job::CM::DumpTopic;

#
# Dump various topic queries to csv and build a gexf file
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/mjm_worker.pl lib/MediaWords/Job/CM/DumpTopic.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/mjm_worker.pl":
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

    my $topics_id = $args->{ topics_id };
    unless ( defined $topics_id )
    {
        die "'topics_id' is undefined.";
    }

    # No transaction started because apparently dump_topic() does start one itself
    MediaWords::CM::Dump::dump_topic( $db, $topics_id );
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
