#!/usr/bin/env perl

# call Downloads::process_download_for_extractor on the given download and print out the download_text and story_sentences that result
use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::Util::HTML;
use MediaWords::StoryVectors;

sub main
{
    my ( $downloads_id ) = @ARGV;

    die( "usage: $0 < downloads_id >" ) unless ( $downloads_id );

    my $db = MediaWords::DB::connect_to_db;

    my $download = $db->find_by_id( 'downloads', $downloads_id ) || die( "Unable to find download" );

    die( "download is not in success/content state" )
      unless ( $download->{ type } = 'content' && $download->{ state } = 'success' );

    MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download );

    my $download_texts = $db->query( "select * from download_texts where downloads_id = ?", $downloads_id )->hashes;

    my $story_sentences = $db->query( <<END, $downloads_id )->hashes;
select ss.* 
    from story_sentences ss join downloads d on ( d.stories_id = ss.stories_id )
    where d.downloads_id = ?
    order by ss.sentence_number
END

    print Dumper( $download_texts );
    print Dumper( $story_sentences );

}

main();
