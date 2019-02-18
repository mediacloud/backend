package MediaWords::Util::Mail;

#
# Email sending helper
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Mail::Message;

{

    package MediaWords::Util::Mail::PythonProxy;

    #
    # Proxy to util/mail.py; used to be able to proxy native Python object ("python_message")
    #

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    import_python_module( __PACKAGE__, 'mediawords.util.mail' );

    1;
}

sub enable_test_mode()
{
    return MediaWords::Util::Mail::PythonProxy::enable_test_mode();
}

sub disable_test_mode()
{
    return MediaWords::Util::Mail::PythonProxy::disable_test_mode();
}

sub send_email($)
{
    my $message = shift;

    my $python_message = $message->{ python_message };
    unless ( $python_message )
    {
        die "python_message is unset.";
    }

    return MediaWords::Util::Mail::PythonProxy::send_email( $python_message );
}

sub send_text_email($$$)
{
    my ( $to_email, $subject, $message_body ) = @_;

    return MediaWords::Util::Mail::PythonProxy::send_text_email( $to_email, $subject, $message_body );
}

1;
