use strict;
use warnings;

use Test::More tests => 10;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Mail;
use MediaWords::Util::Mail::Message::Templates::AuthActivationNeededMessage;
use MediaWords::Util::Mail::Message::Templates::AuthActivatedMessage;
use MediaWords::Util::Mail::Message::Templates::AuthResetPasswordMessage;
use MediaWords::Util::Mail::Message::Templates::AuthPasswordChangedMessage;
use MediaWords::Util::Mail::Message::Templates::AuthAPIKeyResetMessage;

sub main()
{
    # More extensive testing is done on the Python's side
    MediaWords::Util::Mail::enable_test_mode();

    my $to        = 'nowhere@mediacloud.org';
    my $full_name = 'John Doe';

    {
        my $message = MediaWords::Util::Mail::Message::Templates::AuthActivationNeededMessage->new(
            {
                to                      => $to,
                full_name               => $full_name,
                activation_url          => 'https://activate.com/activate.php',
            }
        );
        ok( $message );
        ok( MediaWords::Util::Mail::send_email( $message ) );
    }

    {
        my $message = MediaWords::Util::Mail::Message::Templates::AuthActivatedMessage->new(
            {
                to        => $to,
                full_name => $full_name,
            }
        );
        ok( $message );
        ok( MediaWords::Util::Mail::send_email( $message ) );
    }

    {
        my $message = MediaWords::Util::Mail::Message::Templates::AuthResetPasswordMessage->new(
            {
                to                 => $to,
                full_name          => $full_name,
                password_reset_url => 'https://password.com/reset.php',
            }
        );
        ok( $message );
        ok( MediaWords::Util::Mail::send_email( $message ) );
    }

    {
        my $message = MediaWords::Util::Mail::Message::Templates::AuthPasswordChangedMessage->new(
            {
                to        => $to,
                full_name => $full_name,
            }
        );
        ok( $message );
        ok( MediaWords::Util::Mail::send_email( $message ) );
    }

    {
        my $message = MediaWords::Util::Mail::Message::Templates::AuthAPIKeyResetMessage->new(
            {
                to        => $to,
                full_name => $full_name,
            }
        );
        ok( $message );
        ok( MediaWords::Util::Mail::send_email( $message ) );
    }
}

main();
