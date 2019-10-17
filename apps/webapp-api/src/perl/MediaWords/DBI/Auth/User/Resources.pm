package MediaWords::DBI::Auth::User::Resources;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

{
    # Proxy to Python's implementation
    package MediaWords::DBI::Auth::User::Resources::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    import_python_module( __PACKAGE__, 'webapp.auth.user' );

    1;
}

sub new
{
    my ( $class, %args ) = @_;

    unless ( defined $args{ weekly_requests } ) {
        LOGCONFESS "weekly_requests is unset.";
    }
    unless ( defined $args{ weekly_requested_items } ) {
        LOGCONFESS "weekly_requested_items is unset.";
    }

    my $python_object = MediaWords::DBI::Auth::User::Resources::PythonProxy::Resources->new(
        $args{ weekly_requests },
        $args{ weekly_requested_items },
    );

    my $self = $class->from_python_object( $python_object );

    return $self;
}

sub from_python_object($$)
{
    my ( $class, $python_object ) = @_;

    my $self = {};
    bless $self, $class;

    unless ( $python_object )
    {
        LOGCONFESS "Python user object is not set.";
    }

    $self->{ _python_object } = $python_object;

    return $self;
}

sub weekly_requests($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->weekly_requests();
}

sub weekly_requested_items($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->weekly_requested_items();
}

1;
