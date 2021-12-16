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
            1 AS media_id,
            'http://' AS url,
            'Test Media' AS name
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
            1 AS feeds_id,
            1 AS media_id,
            'Test Feed' AS name,
            'http://' AS url
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
            1 AS stories_id,
            1 AS media_id,
            'http://' AS url,
            'guid' AS guid,
            'Test Story' AS title,
            NOW() AS publish_date,
            NOW() AS collect_date
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
            $MOCK_DOWNLOADS_ID AS downloads_id,
            1 AS feeds_id,
            1 AS stories_id,
            'http://' AS url,
            '' AS host,
            NOW() AS download_time,
            'content' AS type,
            'success' AS state,
            'postgresql:raw_downloads' AS path,
            0 AS priority,
            0 AS sequence
        )
SQL
    );

    return $MOCK_DOWNLOADS_ID;
}

1;
