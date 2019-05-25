package MediaWords::DBI::Auth::Register;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth::User::NewUser;

{
    # Proxy to Python's implementation
    package MediaWords::DBI::Auth::Register::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    import_python_module( __PACKAGE__, 'webapp.auth.register' );

    1;
}

sub _generate_user_activation_token($$$)
{
    my ( $db, $email, $activation_link ) = @_;

    MediaWords::DBI::Auth::Register::PythonProxy::_generate_user_activation_token(
        $db,                 #
        $email,              #
        $activation_link,    #
    );
}

sub send_user_activation_token($$$;$)
{
    my ( $db, $email, $activation_link, $subscribe_to_newsletter ) = @_;

    MediaWords::DBI::Auth::Register::PythonProxy::send_user_activation_token(
        $db,                         #
        $email,                      #
        $activation_link,            #
        $subscribe_to_newsletter,    #
    );
}

sub add_user($$)
{
    my ( $db, $new_user ) = @_;

    unless ( ref( $new_user ) eq 'MediaWords::DBI::Auth::User::NewUser' )
    {
        die "New user is not MediaWords::DBI::Auth::User::NewUser.";
    }

    my $python_object = $new_user->{ _python_object };
    unless ( $python_object )
    {
        die "Python new user object is unset.";
    }

    MediaWords::DBI::Auth::Register::PythonProxy::add_user( $db, $python_object );
}

sub activate_user_via_token($$$)
{
    my ( $db, $email, $activation_token ) = @_;

    MediaWords::DBI::Auth::Register::PythonProxy::activate_user_via_token(
        $db,                  #
        $email,               #
        $activation_token,    #
    );
}

1;
