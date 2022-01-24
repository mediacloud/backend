use strict;
use warnings;
use utf8;

use Readonly;

sub create_mock_download($$)
{
    my ( $db ) = @_;

    Readonly my $MOCK_DOWNLOADS_ID => 12345;

    $db->query( <<SQL
        INSERT INTO media (
            media_id,
            url,
            name
        ) VALUES (
            1,
            'http://',
            'Test Media'
        )
SQL
    );

    $db->query( <<SQL
        INSERT INTO feeds (
            feeds_id,
            media_id,
            name,
            url
        ) VALUES (
            1,
            1,
            'Test Feed',
            'http://'
        )
SQL
    );

    $db->query( <<SQL
        INSERT INTO stories (
            stories_id,
            media_id,
            url,
            guid,
            title,
            publish_date,
            collect_date
        )
        VALUES (
            1,
            1,
            'http://',
            'guid',
            'Test Story',
            NOW(),
            NOW()
        );
SQL
    );

    $db->query( <<"SQL"
        INSERT INTO downloads (
            downloads_id,
            feeds_id,
            stories_id,
            url,
            host,
            download_time,
            type,
            state,
            path,
            priority,
            sequence
        )
        VALUES (
            -- For whatever reason setting $MOCK_DOWNLOADS_ID as a parameter doesn't seem to work
            $MOCK_DOWNLOADS_ID,
            1,
            1,
            'http://',
            '',
            NOW(),
            'content',
            'success',
            'postgresql:raw_downloads',
            0,
            0
        )
SQL
    );

    return $MOCK_DOWNLOADS_ID;
}

1;
