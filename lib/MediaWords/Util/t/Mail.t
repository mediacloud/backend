use strict;
use warnings;

use Test::More tests => 14;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Mail;

sub test_send_email()
{
    my $message = MediaWords::Util::Mail::Message->new(
        {
            to      => 'nowhere@mediacloud.org',
            cc      => 'nowhere+cc@mediacloud.org',
            bcc     => 'nowhere+bcc@mediacloud.org',
            subject => 'Hello!',
            text_body =>
'Text message 𝖜𝖎𝖙𝖍 𝖘𝖔𝖒𝖊 𝖀𝖓𝖎𝖈𝖔𝖉𝖊 𝖈𝖍𝖆𝖗𝖆𝖈𝖙𝖊𝖗𝖘.',
            html_body =>
'<strong>HTML message 𝖜𝖎𝖙𝖍 𝖘𝖔𝖒𝖊 𝖀𝖓𝖎𝖈𝖔𝖉𝖊 𝖈𝖍𝖆𝖗𝖆𝖈𝖙𝖊𝖗𝖘.</strong>',
        }
    );
    ok( MediaWords::Util::Mail::send_email( $message ) );

}

sub test_send_text_email()
{
    my $to      = 'nowhere@mediacloud.org';
    my $subject = 'Hello!';
    my $message =
'This is my message 𝖜𝖎𝖙𝖍 𝖘𝖔𝖒𝖊 𝖀𝖓𝖎𝖈𝖔𝖉𝖊 𝖈𝖍𝖆𝖗𝖆𝖈𝖙𝖊𝖗𝖘.';

    ok( MediaWords::Util::Mail::send_text_email( $to, $subject, $message ) );
}

sub test_email_templates()
{
    # More extensive testing is done on the Python's side

    my $to        = 'nowhere@mediacloud.org';
    my $full_name = 'John Doe';

    {
        my $message = MediaWords::Util::Mail::Message::Templates::AuthActivationNeededMessage->new(
            {
                to                      => $to,
                full_name               => $full_name,
                activation_url          => 'https://activate.com/activate.php',
                subscribe_to_newsletter => 1,
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

    {
        my $message = MediaWords::Util::Mail::Message::Templates::TopicSpiderUpdateMessage->new(
            {
                to                  => $to,
                topic_name          => 'Test topic',
                topic_url           => 'https://topics.com/topic/1',
                topic_spider_status => 'Something new has happened.',
            }
        );
        ok( $message );
        ok( MediaWords::Util::Mail::send_email( $message ) );
    }
}

sub main()
{
    MediaWords::Util::Mail::enable_test_mode();

    test_send_email();
    test_send_text_email();
    test_email_templates();
}

main();
