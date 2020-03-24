package MediaWords::Job::State;

#
# Job state configuration
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

Readonly our $STATE_QUEUED => 'queued';
Readonly our $STATE_RUNNING => 'running';
Readonly our $STATE_COMPLETED => 'completed';
Readonly our $STATE_ERROR => 'error';


sub new($$$)
{
    my ( $class, $table, $state_column, $message_column ) = @_;

    my $self = {};
    bless $self, $class;

    unless ( $table ) {
        LOGDIE "Table is not set.";
    }
    unless ( $state_column ) {
        LOGDIE "State column is not set.";
    }
    unless ( $message_column ) {
        LOGDIE "Message column is not set.";
    }

    $self->{ _table } = $table;
    $self->{ _state_column } = $state_column;
    $self->{ _message_column } = $message_column;

    return $self;
}

sub table($)
{
    my $self = shift;

    return $self->{ _table };
}

sub state_column($)
{
    my $self = shift;

    return $self->{ _state_column };
}

sub message_column($)
{
    my $self = shift;

    return $self->{ _message_column };
}

1;
