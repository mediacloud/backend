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
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::Print;
use Email::Sender::Transport::SMTP;

use IO::Handle;
use Readonly;

# Environment variable that, when set, will prevent the package from actually sending the email
Readonly our $ENV_MAIL_DO_NO_SEND => 'MEDIACLOUD_MAIL_DO_NOT_SEND';

sub enable_test_mode()
{
    $ENV{ $ENV_MAIL_DO_NO_SEND } = 1;
}

sub disable_test_mode()
{
    delete $ENV{ $ENV_MAIL_DO_NO_SEND };
}

# Send email to someone; returns 1 on success, 0 on failure
sub send($$$)
{
    my ( $to_email, $subject, $message_body ) = @_;

    my $config = MediaWords::Util::Config::get_config;

    eval {

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

        my $transport = Email::Sender::Transport::SMTP->new(
            {
                host          => $config->{ mail }->{ smtp }->{ host },
                port          => $config->{ mail }->{ smtp }->{ port },
                ssl           => ( $config->{ mail }->{ smtp }->{ starttls } ? 'starttls' : 0 ),
                sasl_username => $config->{ mail }->{ smtp }->{ username },
                sasl_password => $config->{ mail }->{ smtp }->{ username },
            }
        );

        if ( $ENV{ $ENV_MAIL_DO_NO_SEND } )
        {
            INFO "Test mode is enabled, not actually sending any email";
            my $io = IO::Handle->new_from_fd( fileno( STDERR ), 'w' );
            $transport = Email::Sender::Transport::Print->new( { fh => $io } );
        }

        sendmail( $message, { transport => $transport } );
    };

    if ( $@ )
    {
        ERROR( "Unable to send email to $to_email: $@" );
        return 0;
    }

    return 1;
}

1;
