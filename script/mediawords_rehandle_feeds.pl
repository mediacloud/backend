#!/usr/bin/env perl

# reprocess feed downloads that have had a feed error matching a given message

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib", "$FindBin::Bin";
}

use Data::Dumper;
use Modern::Perl "2015";

use MediaWords::Crawler::FeedHandler;
use MediaWords::DB;
use MediaWords::Util::Config qw(get_config);

sub main
{
    my ( $error_pattern, $date ) = @ARGV;

    die( 'usage: mediawords_rehandle_feeds.pl <error pattern> <date >' ) unless ( $error_pattern && $date );

    my $dnpf = get_config->{ mediawords }->{ do_not_process_feeds };
    die( "set mediawords.do_not_process_feeds to 'no' in mediawords.yml" ) if ( $dnpf && ( $dnpf eq 'yes' ) );

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
            print STDERR "Error rehandling download: $download->{ downloads_id }: $@\n";
            $db = MediaWords::DB::connect_to_db;
        }

    }
}

main();
