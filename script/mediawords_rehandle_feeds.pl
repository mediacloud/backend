#!/usr/bin/env perl

# reprocess feed downloads that have had a feed error matching a given message

use strict;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::Config;

use Data::Dumper;

sub main
{
    my ( $error_pattern, $date ) = @ARGV;

    die( 'usage: mediawords_rehandle_feeds.pl <error pattern> <date >' ) unless ( $error_pattern && $date );

    my $db = MediaWords::DB::connect_to_db;

    my $downloads = $db->query( <<'END', $error_pattern, $date )->hashes;
select distinct a.*, f.url feed_url
    from downloads a
        join feeds f on ( a.feeds_id = f.feeds_id )
    where
        a.state = 'feed_error' and
        a.error_message ~ $1 and
        a.download_time > $2
    order by feed_url
END

    for my $download ( @{ $downloads } )
    {
        eval {
            my $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download );
            DEBUG Dumper( $download );

            if ( length( $$content_ref ) > 32 )
            {
                $download->{ state } = 'error';

                my $handler = MediaWords::Crawler::Engine::handler_for_download( $db, $download );
                $handler->handle_download( $db, $download, $$content_ref );
            }
        };
        if ( $@ )
        {
            ERROR "Error rehandling download: $download->{ downloads_id }: $@";
            $db = MediaWords::DB::connect_to_db;
        }

    }
}

main();
