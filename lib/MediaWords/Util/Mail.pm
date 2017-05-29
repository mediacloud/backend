package MediaWords::Util::Mail;

#
# Email sending helper
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use Email::MIME;
use Email::Sender::Simple;

# used by test_mode() below to make send() only print out messages rather than sending them
my $_test_mode = 0;

# Send email to someone; returns 1 on success, 0 on failure
sub send($$$)
{
    my ( $to_email, $subject, $message_body ) = @_;

    my $config = MediaWords::Util::Config::get_config;

    my $message = Email::MIME->create(
        header_str => [
            From    => $config->{ mail }->{ from_address },
            To      => $to_email,
            Subject => '[Media Cloud] ' . $subject,
        ],
        attributes => {
            encoding => 'quoted-printable',
            charset  => 'UTF-8',
        },
        body_str => <<"EOF"
Hello,

$message_body

--
Media Cloud (www.mediacloud.org)

EOF

    );

    if ( $_test_mode )
    {
        TRACE( "send mail to $to_email: " . $message->body_raw );
        return 1;
    }

    eval { Email::Sender::Simple->send( $message ) };
    if ( $@ )
    {
        ERROR( "Unable to send email to $to_email: $@" );
        return 0;
    }

    return 1;
}

# return the value of test_mode for this module.  if an argument is specified and defined, set test_mode
# to be the new value first.  while test_mode is true, send() will print emails using TRACE instead of sending them.
sub test_mode(;$)
{
    $_test_mode = $_[ 0 ] if ( defined( $_[ 0 ] ) );

    return $_test_mode;
}

1;
