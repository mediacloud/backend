package MediaWords::JobManager::Broker::Null;

#
# Null broker used for initialization
#
# Usage:
#
# MediaWords::JobManager::Broker::Null->new();
#

use strict;
use warnings;
use Modern::Perl "2012";

use Moose;
with 'MediaWords::JobManager::Broker';

use Readonly;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init(
    {
        level  => $DEBUG,
        utf8   => 1,
        layout => "%d{ISO8601} [%P]: %m%n"
    }
);

# flush sockets after every write
$| = 1;

use MediaWords::JobManager;
use MediaWords::JobManager::Job;

# Constructor
sub BUILD
{
    my $self = shift;
    my $args = shift;
}

sub start_worker($$)
{
    my ( $self, $function_name ) = @_;

    LOGDIE( "FIXME not implemented." );
}

sub run_job_sync($$$$)
{
    my ( $self, $function_name, $args, $priority ) = @_;

    LOGDIE( "FIXME not implemented." );
}

sub run_job_async($$$$)
{
    my ( $self, $function_name, $args, $priority ) = @_;

    LOGDIE( "FIXME not implemented." );
}

sub job_id_from_handle($$)
{
    my ( $self, $job_handle ) = @_;

    LOGDIE( "FIXME not implemented." );
}

no Moose;    # gets rid of scaffolding

1;
