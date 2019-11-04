package MediaWords::DBI::Auth::User::NewUser;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth::User::NewOrModifyUser;
our @ISA = qw(MediaWords::DBI::Auth::User::NewOrModifyUser);

sub new
{
    my ( $class, %args ) = @_;

    my $python_object = MediaWords::DBI::Auth::User::AbstractUser::PythonProxy::NewUser->new(
        $args{ email },
        $args{ full_name },
        $args{ notes },
        $args{ active },
        $args{ has_consented },
        $args{ resource_limits }->{ _python_object },
        $args{ password },
        $args{ password_repeat },
        $args{ role_ids },
        $args{ activation_url },
    );

    my $self = $class->SUPER::new( python_object => $python_object );

    return $self;
}

sub activation_url($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->activation_url();
}

1;
