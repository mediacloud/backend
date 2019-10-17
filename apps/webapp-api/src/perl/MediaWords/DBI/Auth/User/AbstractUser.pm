package MediaWords::DBI::Auth::User::AbstractUser;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth::User::Resources;

{
    # Proxy to Python's implementation
    package MediaWords::DBI::Auth::User::AbstractUser::PythonProxy;

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

    my $self = {};
    bless $self, $class;

    unless ( $args{ python_object } )
    {
        LOGCONFESS "Python user object is not set.";
    }

    $self->{ _python_object } = $args{ python_object };

    return $self;
}

sub email($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->email();
}

sub full_name($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->full_name();
}

sub notes($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->notes();
}

sub active($)
{
    my ( $self ) = @_;

    return int( $self->{ _python_object }->active() );
}

sub has_consented($)
{
    my ( $self ) = @_;

    return int( $self->{ _python_object }->has_consented() );
}

sub resource_limits($)
{
    my ( $self ) = @_;

    return MediaWords::DBI::Auth::User::Resources->from_python_object( $self->{ _python_object }->resource_limits() );
}

1;
