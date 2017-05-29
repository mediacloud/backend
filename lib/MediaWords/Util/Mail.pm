package MediaWords::Util::Mail;

#
# Email sending helper
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MediaWords::Util::Mail::Message;

use Email::Stuffer;
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
sub send_email($)
{
    my $message = shift;

    if ( ref( $message ) ne 'MediaWords::Util::Mail::Message' )
    {
        die "Message is not MediaWords::Util::Mail::Message";
    }

    unless ( $message->from() )
    {
        die "'from' is unset.";
    }
    if ( $message->to() and ref( $message->to() ) ne ref [] )
    {
        die "'to' is not arrayref.";
    }
    if ( $message->cc() and ref( $message->cc() ) ne ref [] )
    {
        die "'cc' is not arrayref.";
    }
    if ( $message->bcc() and ref( $message->bcc() ) ne ref [] )
    {
        die "'bcc' is not arrayref.";
    }
    unless ( scalar( @{ $message->to() } ) or scalar( @{ $message->cc() } ) or scalar( @{ $message->bcc() } ) )
    {
        die "No one to send the email to.";
    }
    unless ( $message->subject() )
    {
        die "'subject' is unset.";
    }
    unless ( $message->text_body() or $message->html_body() )
    {
        die "No message body.";
    }

    eval {

        my $config = MediaWords::Util::Config::get_config;

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

        my $to  = $message->to()  ? join( ', ', @{ $message->to() } )  : '';
        my $cc  = $message->cc()  ? join( ', ', @{ $message->cc() } )  : '';
        my $bcc = $message->bcc() ? join( ', ', @{ $message->bcc() } ) : '';

        Email::Stuffer->from( $message->from() )->to( $to )->cc( $cc )->bcc( $bcc )
          ->subject( '[Media Cloud] ' . $message->subject() )->text_body( $message->text_body() )
          ->html_body( $message->html_body() )->header( 'Content-Type', 'text/html; charset=UTF-8' )
          ->transport( $transport )->send();
    };

    if ( $@ )
    {
        ERROR( "Unable to send message to " . join( ', ', @{ $message->to() } ) . ": $@" );
        return 0;
    }

    return 1;
}

# Send text email to someone; returns 1 on success, 0 on failure
sub send_text_email($$$)
{
    my ( $to_email, $subject, $message_body ) = @_;

    my $message = MediaWords::Util::Mail::Message->new(
        {
            to        => $to_email,
            subject   => $subject,
            text_body => <<"EOF",
    Hello,

    $message_body

    --
    Media Cloud (www.mediacloud.org)

EOF
        }
    );

    return send_email( $message );
}

1;
