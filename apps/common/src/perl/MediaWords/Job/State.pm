package MediaWords::Job::State;

#
# Job state configuration
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Job::State::ExtraTable;

use Readonly;

Readonly our $STATE_QUEUED => 'queued';
Readonly our $STATE_RUNNING => 'running';
Readonly our $STATE_COMPLETED => 'completed';
Readonly our $STATE_ERROR => 'error';


sub new($;$)
{
    my ( $class, $extra_table ) = @_;

    my $self = {};
    bless $self, $class;

    if ( $extra_table ) {
        unless ( ref( $extra_table ) eq 'MediaWords::Job::State::ExtraTable' ) {
            LOGDIE "Extra table configuration is not MediaWords::Job::State::ExtraTable";
        }
    }

    $self->{ _extra_table } = $extra_table;

    return $self;
}

sub extra_table($)
{
    my $self = shift;

    return $self->{ _extra_table };
}

1;
