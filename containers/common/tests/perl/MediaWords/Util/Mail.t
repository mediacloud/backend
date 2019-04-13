use strict;
use warnings;

use Test::More tests => 2;

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

sub main()
{
    MediaWords::Util::Mail::enable_test_mode();

    test_send_email();
    test_send_text_email();
}

main();
