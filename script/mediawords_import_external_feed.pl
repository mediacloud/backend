#!/usr/bin/env perl

# import stories from external feeds into existing media source

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/.";
}

use Data::Dumper;
use Getopt::Long;

use MediaWords::Crawler::FeedHandler;
use MediaWords::DB;
use MediaWords::DBI::Downloads;

# import feed from existing mc feed
sub import_mc_feed
{
    my ( $db, $media_id, $feeds_id ) = @_;

    my $downloads = $db->query( <<END, $feeds_id )->hashes;
select * 
    from downloads
    where 
        feeds_id = ? and
        type = 'feed' and
        state = 'success'
    order by download_time
END

    for my $download ( @{ $downloads } )
    {
        my $content_ref = \'';
        eval { $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download ); };

        # skip redundant feeds
        next if ( length( $$content_ref ) < 32 );

        print STDERR "importing download $download->{ downloads_id } $download->{ download_time }\n";

        MediaWords::Crawler::FeedHandler::import_external_feed( $db, $media_id, $$content_ref );
    }

}

# import feed from file
sub import_file_feed
{
    my ( $db, $media_id, $file ) = @_;

    open( FILE, "<$file" ) || die( "Unable to open file '$file': $!" );
    my $content = join( '', <FILE> );
    close( FILE );

    MediaWords::Crawler::FeedHandler::import_external_feed( $db, $media_id, $content );
}

sub main
{
    my ( $media_id, $feeds );

    $feeds = [];

    Getopt::Long::GetOptions(
        "media_id=i" => \$media_id,
        "feed=s"     => $feeds
    ) || return;

    die( "usage: $0 --media_id < media_id > --feed < filename > [ --feed < filename > ... ]" )
      unless ( $media_id && @{ $feeds } );

    my $db = MediaWords::DB::connect_to_db;

    for my $feed ( @{ $feeds } )
    {
        if ( $feed =~ /^\d+$/ )
        {
            import_mc_feed( $db, $media_id, $feed );
        }
        else
        {
            import_file_feed( $db, $media_id, $feed );
        }
    }
}

main();
