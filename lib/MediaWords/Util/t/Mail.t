use strict;
use warnings;

use Test::More tests => 1;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Mail;

sub test_send()
{
    my $to      = 'nowhere@mediacloud.org';
    my $subject = 'Hello!';
    my $message = 'This is my message.';

    ok( MediaWords::Util::Mail::send_text_email( $to, $subject, $message ) );
}

sub main()
{
    MediaWords::Util::Mail::enable_test_mode();

    test_send();
}

main();
