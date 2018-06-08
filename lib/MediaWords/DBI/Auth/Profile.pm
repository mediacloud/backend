package MediaWords::DBI::Auth::Profile;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth::User::CurrentUser;
use MediaWords::DBI::Auth::User::ModifyUser;

{
    # Proxy to Python's implementation
    package MediaWords::DBI::Auth::Profile::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    import_python_module( __PACKAGE__, 'mediawords.dbi.auth.profile' );

    1;
}

sub all_users($)
{
    my ( $db ) = @_;

    my $python_objects = MediaWords::DBI::Auth::Profile::PythonProxy::all_users( $db );

    my $perl_objects = [];

    foreach my $python_object ( @{ $python_objects } )
    {
        my $perl_object = MediaWords::DBI::Auth::User::CurrentUser->new( python_object => $python_object );
        push( @{ $perl_objects }, $perl_object );
    }

    return $perl_objects;
}

sub update_user($$)
{
    my ( $db, $existing_user ) = @_;

    unless ( ref( $existing_user ) eq 'MediaWords::DBI::Auth::User::ModifyUser' )
    {
        die "Existing user is not MediaWords::DBI::Auth::User::ModifyUser.";
    }

    my $python_object = $existing_user->{ _python_object };
    unless ( $python_object )
    {
        die "Python existing user object is unset.";
    }

    MediaWords::DBI::Auth::Profile::PythonProxy::update_user( $db, $python_object );
}

sub delete_user($$)
{
    my ( $db, $email ) = @_;

    MediaWords::DBI::Auth::Profile::PythonProxy::delete_user( $db, $email );
}

sub regenerate_api_key($$)
{
    my ( $db, $email ) = @_;

    MediaWords::DBI::Auth::Profile::PythonProxy::regenerate_api_key( $db, $email );
}

1;
