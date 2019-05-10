package MediaWords::JobManager::Worker;

#
# Worker helpers
#

use strict;
use warnings;
use Modern::Perl "2015";

use MediaWords::AbstractJob;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init( { level => $DEBUG, utf8 => 1, layout => "%d{ISO8601} [%P]: %m%n" } );

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
