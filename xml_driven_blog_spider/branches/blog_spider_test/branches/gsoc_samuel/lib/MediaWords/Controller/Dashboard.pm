package MediaWords::Controller::Dashboard;

use strict;
use warnings;
use parent 'Catalyst::Controller';

use DBIx::Simple;
use HTML::TagCloud;
use URI::Escape;

sub index : Path : Args(0)
{
    return list(@_);
}

# list the possible word cloud topics
sub list : Local
{
    my ( $self, $c ) = @_;
    
    my $media = $c->dbis->query("select * from media order by name asc")->hashes;
    
    $c->stash->{media} = $media;
    $c->stash->{template} = 'dashboard/list.tt2';
}

# get the html for a word cloud of the s
sub get_medium_word_cloud
{
    my ( $self, $c, $medium, $date_string, $words ) = @_;
    
    my $cloud = HTML::TagCloud->new;

    for my $word (@{$words}) 
    {
        # my $url = $c->uri_for( "/dashboard/sentences/$medium->{media_id}/$date_string/$word->{stem}" );
        my $url = '';
        $cloud->add( $word->{ term }, $url, $word->{ stem_count } );        
    }
    my $chart_html = $cloud->html(@{$words});
    
    return $chart_html;

}

# view the dashboard page for a media source
sub medium : Local
{
    my ( $self, $c, $media_id, $date_string ) = @_;
    
    my $medium = $c->dbis->query("select * from media where media_id = ?", $media_id)->hash ||
        die( "unknown medium: $media_id" );
    
    $date_string ||= '2008-08-01';
    $date_string =~ /^([0-9]+)-([0-9]+)-([0-9]+)$/ ||
        die( "unknown date: $date_string" );

    #my $date = timelocal(0, 0, 0, $3, $2 - 1, $1 - 1900);        
        
    my $words = $c->dbis->query( "select * from weekly_media_words " .
                                 "  where media_id = ? and " . 
                                 "    publish_week >= date_trunc('week', date '$date_string') and " .
                                 "    publish_week < date_trunc('week', date '$date_string' + interval '1 week') and " .
                                 "    not is_stop_stem('long', stem) " .
                                 "  order by stem_count desc " .
                                 "  limit 100", $medium->{ media_id } )->hashes; 
                                 
    my $word_cloud = $self->get_medium_word_cloud($c, $medium, $date_string, $words);
    
    # my $sentences = $c->dbis->query( "select ss.* from story_sentences ss, story_sentence_words ssw " .
    #                                  "  where ss.stories_id = ssw.stories_id and ss.sentence_number = ssw.sentence_number and " .
    #                                  "    ssw.stem = ? and ssw.publish_date >= date_trunc('week', date '$date_string') and " .
    #                                  "    ssw.publish_date < date_trunc('week', date '$date_string' + interval '1 week') " .
    #                                  "  order by publish_date asc limit 100",
    #                                  $words->[0]->{ stem } );
    
    print STDERR "cloud: $word_cloud\n";
    
    $c->stash->{medium} = $medium;
    $c->stash->{word_cloud} = $word_cloud;
    $c->stash->{date_string} = $date_string;
    # $c->stash->{sentences} = $sentences;
    $c->stash->{template} = 'dashboard/view.tt2';
}


1;