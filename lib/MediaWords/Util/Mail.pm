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

# Send email to someone; returns 1 on success, 0 on failure
sub send($$$;$)
{
    my ( $to_email, $subject, $message_body, $replyto_email ) = @_;

    if ( !$replyto_email )
    {
        $replyto_email = $to_email;
    }

    my $config = MediaWords::Util::Config::get_config;

    my $message = Email::MIME->create(
        header_str => [
            From    => $config->{ mail }->{ from_address },
            To      => $to_email,
            ReplyTo => $replyto_email,
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

    my $smtp = $config->{ smtp };
    if ( $smtp->{ test } && ( $smtp->{ test } eq 'yes' ) )
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

1;
