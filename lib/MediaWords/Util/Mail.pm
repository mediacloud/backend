package MediaWords::Util::Mail;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

#
# Email sending helper
#

use strict;
use warnings;

use MediaWords::Util::Config;
use Email::MIME;
use Email::Sender::Simple qw(try_to_sendmail);

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

    if ( try_to_sendmail( $message ) )
    {
        return 1;
    }
    else
    {
        say STDERR "Unable to send email to $to_email";
        return 0;
    }
}

1;
