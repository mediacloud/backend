#!/usr/bin/env perl

# import stories using one of the MediaWords::ImportStories::* modules

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::ImportStories::ScrapeHTML;
use MediaWords::ImportStories::Feedly;

sub main
{
    my $p = {};

    Getopt::Long::GetOptions(
        $p,                  "start_url=s", "story_url_pattern=s", "page_url_pattern=s",
        "content_pattern=s", "media_id=i",  "start_date=s",        "end_date=s",
        "max_pages=i",       "debug!",      "dry_run!",            "feed_url=s",
        "import_module=s"
    ) || return;

    if ( !( $p->{ media_id } && $p->{ import_module } ) )
    {
        die( "usage: $0 ---media_id <id> --import_module <import module>" );
    }

    my $import_modules = {
        'scrapehtml' => 'ScrapeHTML',
        'feedly'     => 'Feedly'
    };

    if ( my $module = $import_modules->{ $p->{ import_module } } )
    {
        delete( $p->{ import_module } );

        $p->{ db } = MediaWords::DB::connect_to_db;

        my $medium = $p->{ db }->find_by_id( 'media', $p->{ media_id } );
        die( "Unable to find media id '$p->{ media_id }'" ) unless $medium;

        eval( 'MediaWords::ImportStories::' . $module . '->new( $p )->scrape_stories()' );
        die( $@ ) if ( $@ );
    }
    else
    {
        die( "Unknown import module '$p->{ import_module }'" );
    }
}

main();
