use strict;
use warnings;
use utf8;

use Readonly;

sub create_mock_download($$)
{
    my ( $db ) = @_;

    Readonly my $MOCK_DOWNLOADS_ID => 12345;

    $db->query(
        <<EOF
		INSERT INTO media (media_id, url, name)
		VALUES (1, 'http://', 'Test Media')
EOF
    );

    $db->query(
        <<EOF
		INSERT INTO feeds(feeds_id, media_id, name, url)
		VALUES (1, 1, 'Test Feed', 'http://')
EOF
    );

    $db->query(
        <<EOF
		INSERT INTO stories (stories_id, media_id, url, guid, title, publish_date, collect_date)
		VALUES (1, 1, 'http://', 'guid', 'Test Story', now(), now());
EOF
    );

    $db->query(
        <<"SQL"
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
            now(),
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
