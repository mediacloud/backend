package MediaWords::TM::Alert;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Config::TopicsBase;
use MediaWords::Util::Mail;

# send an alert about significant activity on the topic to all users with at least write access to the topic
sub send_topic_alert($$$)
{
    my ( $db, $topic, $message ) = @_;

    my $users = $db->query( <<SQL, $topic->{ topics_id } )->hashes;
select distinct au.*
    from auth_users au
        join topic_permissions tp using ( auth_users_id )
    where
        tp.permission in ( 'admin', 'write' ) and
        tp.topics_id = ?
SQL

    my $emails = [ map { $_->{ email } } @{ $users } ];

    if ( my $topic_alert_emails = MediaWords::Util::Config::TopicsBase::topic_alert_emails() )
    {
        push( @{ $emails }, @{ $topic_alert_emails } );
    }

    my $emails_lookup = {};
    map { $emails_lookup->{ lc( $_ ) } = 1 } @{ $emails };
    $emails = [ keys( %{ $emails_lookup } ) ];

    for my $email ( @{ $emails } )
    {
        my $message = MediaWords::Util::Mail::Message::Templates::TopicSpiderUpdateMessage->new(
            {
                to                  => $email,
                topic_name          => $topic->{ name },
                topic_url           => "https://topics.mediacloud.org/#/topics/$topic->{ topics_id }/summary",
                topic_spider_status => $message,
            }
        );
        MediaWords::Util::Mail::send_email( $message );
    }

}

1;
