package MediaWords::Job::State::ExtraTable;

#
# Job state configuration for reporting to an extra table in addition to "job_states"
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;


sub new($$$$)
{
    my ( $class, $table_name, $state_column, $message_column ) = @_;

    my $self = {};
    bless $self, $class;

    unless ( $table_name ) {
        LOGDIE "Table name is not set.";
    }
    unless ( $state_column ) {
        LOGDIE "State column is not set.";
    }
    unless ( $message_column ) {
        LOGDIE "Message column is not set.";
    }

    $self->{ _table_name } = $table_name;
    $self->{ _state_column } = $state_column;
    $self->{ _message_column } = $message_column;

    return $self;
}

sub table_name($)
{
    my $self = shift;

    return $self->{ _table_name };
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
