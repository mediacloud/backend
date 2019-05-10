package MediaWords::JobManager::Worker;

#
# Worker helpers
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::AbstractJob;

# Run worker
sub start_worker($)
{
    my ( $function_name ) = @_;

    my $broker = MediaWords::AbstractJob::broker();

    INFO( "Starting function '$function_name'..." );
    $broker->start_worker( $function_name );
    INFO( "Done." );
}

1;
