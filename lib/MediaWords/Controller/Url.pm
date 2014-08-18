package MediaWords::Controller::Url;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;
use parent 'Catalyst::Controller';

use JSON;

use MediaWords::DB;

sub index : Path : Args(0)
{
    return data( @_ );
}

# get data for all media matching the given url
sub get_media
{
    my ( $db, $url ) = @_;

    my $media = $db->query( "select m.media_id, m.name, m.url, m.full_text_rss from media m where url = ?", $url )->hashes;

    for my $medium ( @{ $media } )
    {
        $medium->{ feed_urls } = $db->query( "select url from feeds where media_id = ?", $medium->{ media_id } )->hashes;
        $medium->{ last_week_stem_counts } = $db->query(
            "select publish_week, stem, term, stem_count from top_500_weekly_words " . "  where publish_week in " .
              "      ( select publish_week from total_top_500_weekly_words t, media_sets_media_map msmm " .
"          where t.media_sets_id = msmm.media_sets_id and msmm.media_id = ? order by publish_week desc limit 1 ) "
              . "    and mediaurce_id = ? "
              . "  order by stem_count desc",
            $medium->{ media_id },
            $medium->{ media_id }
        )->hashes;
    }
}

# get data for all stories matching the given url
sub get_stories
{
    my ( $db, $url ) = @_;

    my $query = <<END;
select s.*, m.name media_name, m.url media_url, m.full_text_rss media_full_text_rss 
  from stories s, media m where s.media_id = m.media_id and s.url = ?
END

    my $stories = $db->query( $query, $url )->hashes;

    for my $story ( @{ $stories } )
    {
        $story->{ feed_urls } =
          $db->query( "select f.url from feeds f, feeds_stories_map fsm where f.feeds_id = fsm.feeds_id and stories_id = ?",
            $story->{ stories_id } )->hashes;
        $story->{ stem_counts } = $db->query(
            "select stem, min( term ) term, sum( stem_count ) as stem_count from story_sentence_words " .
              "  where stories_id = ? group by stem order by sum( stem_count ) desc",
            $story->{ stories_id }
        )->hashes;
    }

    return $stories;
}

# return a json object with all of our interesting public data about a given url.
# returns a list of matching stories and a list of matching media sources.
sub data : Local
{
    my ( $self, $c ) = @_;

    my $url = $c->req->param( 'url' );

    $c->res->content_type( 'application/json; charset=UTF-8' );

    if ( !$url )
    {
        $c->res->body( encode_json( { error => 1, message => 'must specify a url' } ) );
        return;
    }

    my $stories = get_stories( $c->dbis, $url );

    my $media = get_media( $c->dbis, $url );

    if ( !@{ $stories } && !@{ $media } )
    {
        $c->res->body( encode_json( { error => 1, message => "no stories or media found for the url '$url'" } ) );
        return;
    }

    $c->res->body( encode_json( { stories => $stories, media => $media } ) );

    return;
}

1;
