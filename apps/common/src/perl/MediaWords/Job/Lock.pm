package MediaWords::Job::Lock;

#
# Job lock configuration
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;


sub new($$$)
{
    my ( $class, $lock_type, $lock_arg ) = @_;

    my $self = {};
    bless $self, $class;

    unless ( $lock_type ) {
        LOGDIE "Lock type is not set.";
    }
    unless ( $lock_arg ) {
        LOGDIE "Lock argument is not set.";
    }

    $self->{ _lock_type } = $lock_type;
    $self->{ _lock_arg } = $lock_arg;

    return $self;
}

sub lock_type($)
{
    my $self = shift;

    return $self->{ _lock_type };
}

sub lock_arg($)
{
    my $self = shift;

    return $self->{ _lock_arg };
}

1;
