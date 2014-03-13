#!/usr/bin/env perl

# reprocess feed downloads that have had a feed error.
#
# reprocess all downloads back to a given date in any feed that
# has a download with an error_message matching the given message

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib", "$FindBin::Bin";
}

use Data::Dumper;
use Modern::Perl "2013";

use MediaWords::DB;
use MediaWords::Crawler::FeedHandler;

sub main
{
    my ( $error_pattern, $date ) = @ARGV;

    die( 'usage: mediawords_rehandle_feeds.pl <error pattern> <date >' ) unless ( $error_pattern && $date );

    my $db = MediaWords::DB::connect_to_db;

    my $downloads = $db->query( <<'END', $error_pattern, $date )->hashes;
select distinct a.*, f.url feed_url
    from downloads a
        join feeds f on ( a.feeds_id = f.feeds_id )
        join downloads b on ( f.feeds_id = b.feeds_id )
    where
        a.state = 'feed_error' and
        b.state = 'feed_error' and
        b.error_message ~ $1 and
        b.download_time > $2
    order by feed_url
END

    for my $download ( @{ $downloads } )
    {
        eval {
            my $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download );
            print STDERR Dumper( $download );
            print STDERR substr( $$content_ref, 0, 1024 );

            if ( length( $$content_ref ) > 32 )
            {
                $download->{ state } = 'error';
                MediaWords::Crawler::FeedHandler::handle_feed_content( $db, $download, $$content_ref );
            }
        };
        if ( $@ )
        {
            print STDERR "Error rehandling download: $download->{ downloads_id }\n";
            $db = MediaWords::connect_to_db;
        }

    }
}

main();
