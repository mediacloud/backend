package MediaWords::Job::Broker;

#
# Celery job broker
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Job::Lock;


use Inline Python => <<'PYTHON';

from typing import Dict, Callable, Type, Any, Optional

from mediawords.job import JobBroker, JobLock
from mediawords.util.perl import decode_object_from_bytes_if_needed


class PerlJobBroker(JobBroker):
    """Job broker subclass which does some Perl-Python compatibility magic."""

    def __init__(self, queue_name: str):
        queue_name = decode_object_from_bytes_if_needed(queue_name)
        super().__init__(queue_name=queue_name)

    def run_remotely(self, kwargs: Dict[str, Any]) -> Any:
        kwargs = decode_object_from_bytes_if_needed(kwargs)
        return super().run_remotely(**kwargs)

    def add_to_queue(self, kwargs: Dict[str, Any]) -> str:
        kwargs = decode_object_from_bytes_if_needed(kwargs)
        return super().add_to_queue(**kwargs)

    def get_result(self, job_id: str, timeout: Optional[int] = None) -> Any:
        job_id = decode_object_from_bytes_if_needed(job_id)

        if isinstance(timeout, bytes):
            timeout = decode_object_from_bytes_if_needed(timeout)

        if timeout is not None:
            timeout = int(timeout)

        return super().get_result(job_id=job_id, timeout=timeout)

    def start_worker(self, handler: Callable, lock: object = None):

        def worker_wrapper(*args, **kwargs):
            if args:
                raise Exception(f"Perl workers don't support args, use kwargs instead: {args}")

            return handler(kwargs)

        # Recreate JobLock object from Perl argument
        if lock:
            lock = JobLock(
                lock_type=lock.lock_type(),
                lock_arg=lock.lock_arg(),
            )
        else:
            lock = None

        super().start_worker(handler=worker_wrapper, lock=lock)

PYTHON


sub new($$)
{
    my ( $class, $queue_name ) = @_;

    my $self = {};
    bless $self, $class;

    unless ( $queue_name ) {
        LOGDIE "Queue name is not set.";
    }

    $self->{ _app } = MediaWords::Job::Broker::PerlJobBroker->new( $queue_name );

    return $self;
}

sub queue_name($)
{
    my ( $self ) = @_;

    return $self->{ _app }->queue_name();
}

sub run_remotely($;$)
{
    my ( $self, $args ) = @_;

    unless ( $args ) {
        $args = {};
    }
    unless ( ref($args) eq ref({})) {
        LOGDIE "Args is not a hashref: " . Dumper( $args );
    }

    my $result = $self->{ _app }->run_remotely( $args );

    return $result;
}

sub add_to_queue($;$)
{
    my ( $self, $args ) = @_;

    unless ( $args ) {
        $args = {};
    }
    unless ( ref($args) eq ref({}) ) {
        LOGDIE "Args is not a hashref: " . Dumper( $args );
    }

    my $job_id = $self->{ _app }->add_to_queue( $args );

    return $job_id;
}

sub get_result($$;$)
{
    my ( $self, $job_id, $timeout ) = @_;

    unless ( $job_id ) {
        LOGDIE "Job ID is not set";
    }

    if ( defined $timeout ) {
        $timeout = int( $timeout );
    }

    my $result = $self->{ _app }->get_result( $job_id, $timeout );

    return $result;
}

sub start_worker($$;$)
{
    my ( $self, $handler, $lock ) = @_;

    unless ( ref( $handler ) eq ref( sub {} )) {
        LOGDIE "Handler is not a subref: " . Dumper( $handler );
    }

    if ( $lock ) {
        unless ( ref( $lock ) eq 'MediaWords::Job::Lock' ) {
            LOGDIE "Job lock configuration is not of type MediaWords::Job::Lock.";
        }
    }

    $self->{ _app }->start_worker( $handler, $lock );
}

1;
