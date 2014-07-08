#!/usr/bin/env perl

# generate Data::Dumper dump of story info for evaluating date guessing.  Either generate a new sample
# of stories by randomly picking 100 controversy stories or by using an existing csv of story ids,
# publish dates, and urls.  The resulting data dump will have the following fields for each story:
# * stories_id
# * publish_date
# * url
# * source_link_publish_date
# * html

# usage: generate_date_guessing_sample.pl [<old story dates csv>]

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::Util::CSV;

sub get_stories
{
    my ( $db, $file ) = @_;

    if ( $file )
    {
        return MediaWords::Util::CSV::get_csv_as_hashes( $file );
    }
    else
    {
        return $db->query( <<END )->hashes;
select s.stories_id, s.url, s.publish_date 
    from 
        stories s, controversy_stories cs, tags t, tag_sets ts, stories_tags_map stm 
    where 
        cs.stories_id = s.stories_id and 
        s.stories_id = stm.stories_id and 
        t.tags_id = stm.tags_id and 
        t.tag_sets_id = ts.tag_sets_id and 
        ts.name = 'date_guess_method' and 
        t.tag not in ( 'merged_story_rss', 'guess_by_url_and_date_text', 'guess_by_url' ) 
    order by random() 
    limit 100;
END

    }
}

# get the publish date of the first story found in controversy_links that linked
# to the given story
sub get_source_link_publish_date
{
    my ( $db, $story ) = @_;

    my $source_story = $db->query( <<END, $story->{ stories_id } )->hash;
select s.* from controversy_links cl, stories s
    where 
        cl.ref_stories_id = ? and
        cl.stories_id = s.stories_id
    limit 1
END

    return $source_story ? $source_story->{ publish_date } : undef;
}

sub main
{
    my ( $file ) = @ARGV;

    my $db = MediaWords::DB::connect_to_db;

    my $stories = get_stories( $db, $ARGV[ 0 ] );

    for my $story ( @{ $stories } )
    {
        $story->{ source_link_publish_date } = get_source_link_publish_date( $db, $story );
        $story->{ html } = MediaWords::DBI::Stories::get_initial_download_content( $db, $story );
    }

    print Dumper( $stories );
}

main();
