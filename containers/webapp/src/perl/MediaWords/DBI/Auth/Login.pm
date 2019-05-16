package MediaWords::DBI::Auth::Login;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth::User::CurrentUser;

{
    # Proxy to Python's implementation
    package MediaWords::DBI::Auth::Login::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    import_python_module( __PACKAGE__, 'webapp.auth.login' );

    1;
}

sub login_with_email_password($$$;$)
{
    my ( $db, $email, $password, $ip_address ) = @_;

    my $python_object = MediaWords::DBI::Auth::Login::PythonProxy::login_with_email_password(
        $db,            #
        $email,         #
        $password,      #
        $ip_address,    #
    );

    my $perl_object = MediaWords::DBI::Auth::User::CurrentUser->new( python_object => $python_object );

    return $perl_object;
}

sub login_with_api_key($$$)
{
    my ( $db, $api_key, $ip_address ) = @_;

    my $python_object = MediaWords::DBI::Auth::Login::PythonProxy::login_with_api_key(
        $db,            #
        $api_key,       #
        $ip_address,    #
    );

    my $perl_object = MediaWords::DBI::Auth::User::CurrentUser->new( python_object => $python_object );

    return $perl_object;
}

1;
