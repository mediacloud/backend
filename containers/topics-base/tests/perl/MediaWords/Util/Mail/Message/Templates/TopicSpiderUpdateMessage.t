#!/usr/bin/env prove

use strict;
use warnings;

use Test::More tests => 2;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Mail;
use MediaWords::Util::Mail::Message::Templates::TopicSpiderUpdateMessage;

sub main()
{
    MediaWords::Util::Mail::enable_test_mode();

    # More extensive testing is done on the Python's side

    my $to        = 'nowhere@mediacloud.org';
    my $full_name = 'John Doe';

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

main();
