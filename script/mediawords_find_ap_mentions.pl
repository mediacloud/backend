#!/usr/bin/env perl

# get random stories from MSM during 2015-04-01 - 2015-07-01 that include 'associated press' in the content or '(ap)'
# in the download text

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Encode;
use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::DBI::Stories;

sub get_story_content
{
    my ( $db, $story ) = @_;

    my $content_ref;

    eval { $content_ref = MediaWords::DBI::Stories::get_content_for_first_download( $db, $story ) };
    if ( $@ || !$content_ref )
    {
        warn( "error fetching content: $@" );
        return 0;
    }

    return $$content_ref;
}

sub insert_story_mentions
{
    my ( $db, $stories ) = @_;

    my $values_list = join( ',', map { "($_->{ stories_id })" } @{ $stories } );

    $db->query( "insert into scratch.ap_story_mentions (stories_id) values $values_list" );
}

sub main
{
    my ( $num_stories ) = @ARGV;

    die( "usage: $0 <num stories>" ) unless ( $num_stories );

    my $db = MediaWords::DB::connect_to_db;

    my $stories = $db->query( <<SQL )->hashes;
select s.*, dt.download_text
    from stories s
        join downloads d on ( s.stories_id = d.stories_id  and d.sequence = 1 )
        join download_texts dt on ( dt.downloads_id = d.downloads_id )
        join media_tags_map mtm on ( mtm.media_id = s.media_id )
    where
        mtm.tags_id in ( 8875027,2453107 ) and
        date_trunc( 'day', publish_date ) between '2015-04-01' and '2015-04-07'
    order by md5( s.stories_id::text )
    limit $num_stories
SQL

    my $stories_queue = [];
    for my $story ( @{ $stories } )
    {
        say STDERR "checking $story->{ stories_id } ...";
        if ( !( $story->{ download_text } =~ /\(ap\)/i ) )
        {
            my $content = get_story_content( $db, $story );
            next if ( !( $content =~ /associated press/i ) );
        }

        say STDERR "AP MATCH";

        push( @{ $stories_queue }, $story );
        if ( !( @{ $stories_queue } % 100 ) )
        {
            insert_story_mentions( $db, $stories_queue );
            $stories_queue = [];
        }
    }

    insert_story_mentions( $db, $stories_queue );
}

main();
