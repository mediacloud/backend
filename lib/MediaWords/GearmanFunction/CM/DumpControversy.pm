package MediaWords::GearmanFunction::CM::DumpControversy;

#
# Dump various controversy queries to csv and build a gexf file
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/CM/DumpControversy.pm
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

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::CM::Dump;
use MediaWords::DB;
use MediaWords::DBI::Controversies;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    my $controversy_opt = $args->{ controversy_opt };
    unless ( $controversy_opt )
    {
        die "'controversy_opt' argument is missing.";
    }

    my $db = MediaWords::DB::connect_to_db();
    my $controversies = MediaWords::DBI::Controversies::require_controversies_by_opt( $db, $controversy_opt );
    $db->disconnect;

    for my $controversy ( @{ $controversies } )
    {
        $db = MediaWords::DB::connect_to_db();

        print "CONTROVERSY $controversy->{ name } \n";
        MediaWords::CM::Dump::dump_controversy( $db, $controversy->{ controversies_id } );

        $db->disconnect;
    }
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
