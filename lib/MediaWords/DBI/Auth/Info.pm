package MediaWords::DBI::Auth::Info;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth::User::CurrentUser;

{
    # Proxy to Python's implementation
    package MediaWords::DBI::Auth::Info::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    import_python_module( __PACKAGE__, 'mediawords.dbi.auth.info' );

    1;
}

sub user_info($$)
{
    my ( $db, $email ) = @_;

    my $python_object = MediaWords::DBI::Auth::Info::PythonProxy::user_info( $db, $email );

    my $perl_object = MediaWords::DBI::Auth::User::CurrentUser->new( python_object => $python_object );

    return $perl_object;
}

1;
