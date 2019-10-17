package MediaWords::DBI::Auth::User::ModifyUser;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth::User::NewOrModifyUser;
our @ISA = qw(MediaWords::DBI::Auth::User::NewOrModifyUser);

sub new
{
    my ( $class, %args ) = @_;

    my $python_object = MediaWords::DBI::Auth::User::AbstractUser::PythonProxy::ModifyUser->new(
        $args{ email },
        $args{ full_name },
        $args{ notes },
        $args{ active },
        $args{ resource_limits }->{ _python_object },
        $args{ password },
        $args{ password_repeat },
        $args{ role_ids },
    );

    my $self = $class->SUPER::new( python_object => $python_object );

    return $self;
}

1;
