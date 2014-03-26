#!/usr/bin/env perl

# set media.foreign_rss_links to true for any media use foreign links in their rss feeds, which can confuse some analyses.
# we detect those media by just looking at urls of the last 200 stories from the feed, parsing out the domain from each,
# and marking foreign_rss_links to true for any medium that has more than MAX_DIFFERENT_DOMAINS different domains

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Util::CSV;
use MediaWords::DBI::Media;

use constant MAX_DIFFERENT_DOMAINS => 10;

sub main
{
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    my $media = $db->query( <<END )->hashes;
select * from media where foreign_rss_links = 'f' or foreign_rss_links is null order by media_id
END

    #     where ( foreign_rss_links is null or foreign_rss_links is false ) and
    #         media_id in ( select media_id from sopa_stories ss, stories s where ss.stories_id = s.stories_id )
    #     order by media_id
    # END

    my $i = 0;
    for my $medium ( @{ $media } )
    {
        my $domain_map = MediaWords::DBI::Media::get_medium_domain_counts( $db, $medium );

        my $num_domains = scalar( values( %{ $domain_map } ) );

        my $foreign_rss_links = ( $num_domains > MAX_DIFFERENT_DOMAINS ) ? 't' : 'f';

        print STDERR "$medium->{ name } [ $medium->{ media_id } ]: $num_domains - $foreign_rss_links\n";

        $db->query( "update media set foreign_rss_links = ? where media_id = ?", $foreign_rss_links, $medium->{ media_id } );

        $medium->{ foreign_rss_links } = $foreign_rss_links;
        $medium->{ num_domains }       = $num_domains;

        my $domain_counts = [];
        while ( my ( $domain, $count ) = each( %{ $domain_map } ) )
        {
            push( @{ $domain_counts }, "[ $domain $count ]" );
        }

        $medium->{ domain_counts } = join( " ", @{ $domain_counts } );
    }

# print MediaWords::Util::CSV::get_hashes_as_encoded_csv( $media, [ qw(name url media_id foreign_rss_links num_domains domain_counts) ] );

}

main();
