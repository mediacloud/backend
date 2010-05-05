package MediaWords::Controller::Stats;

use strict;
use warnings;
use parent 'Catalyst::Controller';

use Locale::Country;
use URI::Escape;
use DBIx::Simple;

sub index : Path : Args(0)
{

    return media_tag_counts(@_);
}

# get the url of a chart image for the given tag counts
sub get_tag_count_chart_url
{
    my ( $self, $c, $tag_counts, $title ) = @_;

    if ( !$tag_counts->[0] )
    {
        return "";
    }

    my $max_tag_count = $tag_counts->[0]->{tag_count};
    my $data          = join( ',', map { int( ( $_->{tag_count} / $max_tag_count ) * 100 ) } @{$tag_counts} );
    my $tags          = join( '|', reverse map { uri_escape( $_->{tag} ) } @{$tag_counts} );
    my $esc_title     = uri_escape($title);

    my $url = "http://chart.apis.google.com/chart?cht=bhs&chs=350x300&chd=t:$data&chxt=y&chxl=0:|$tags&chtt=$esc_title";
}

# get the url of a chart image for the given tag counts
sub get_tag_count_map_url
{
    my ( $self, $c, $medium ) = @_;


     my $ret = $c->dbis->query("select  chart_url  from media_map_chart_url where media_id = ?", $medium->{media_id})->flat()->[0];

    return $ret;
}

# generate and stash the medium, media_tag_counts, and chart_url template
# for the given num
sub stash_media_tag_counts
{
    my ( $self, $c, $tag_query, $use_countries, $tag_sets_id, $num ) = @_;

    my $media_id = $c->request->param( 'media_id_' . $num );

    if ( !$media_id )
    {
        return;
    }

    my $medium = $c->dbis->find_by_id( 'media', $media_id );

    if ( !$medium )
    {
        die("Unable to find medium $media_id");
    }

    my @media_tag_counts;
    if ($use_countries)
    {

    }
    elsif ($tag_query)
    {
        @media_tag_counts = $c->dbis->query(
            "select c.*, tt.tag from media_tag_tag_counts c, tags t, tags tt "
              . "where c.tag_tags_id = tt.tags_id and t.tag like ? "
              . "and c.tags_id = t.tags_id and c.media_id = ? "
              . "order by c.tag_count desc limit 10",
            "%$tag_query%", $media_id
        )->hashes;
    }
    else
    {
        @media_tag_counts = $c->dbis->query(
            "select c.*, t.tag from media_tag_counts c, tags t "
              . "where c.tags_id = t.tags_id and c.media_id = ? order by c.tag_count desc limit 10",
            $media_id
        )->hashes;
    }

    my $chart_url =
        $use_countries
      ? $self->get_tag_count_map_url( $c, $medium )
      : $self->get_tag_count_chart_url($c, \@media_tag_counts, $medium->{name} );

    $c->stash->{medium}->{$num}           = $medium;
    $c->stash->{media_tag_counts}->{$num} = \@media_tag_counts;
    $c->stash->{chart_url}->{$num}        = $chart_url;
}

# return the top ten tags for the given medium
sub media_tag_counts : Local
{
    my ( $self, $c ) = @_;

    my $tags        = [];
    my $tag_sets_id = $c->request->param('tag_sets_id');
    $tag_sets_id ||= $c->dbis->find_or_create( 'tag_sets', { name => 'NYTTopics' } )->{tag_sets_id};

    my $tag_query     = $c->request->param('tag_query');
    my $use_countries = $c->request->param('use_countries');

    for my $i ( 1 .. 3 )
    {
        $self->stash_media_tag_counts( $c, $tag_query, $use_countries, $tag_sets_id, $i );
    }

    my @all_media = $c->dbis->query("select * from media order by name asc")->hashes;

    # increase from 1000 to handle all media sources
    $Template::Directive::WHILE_MAX = 2000;

    $c->stash->{use_countries} = $use_countries;
    $c->stash->{tag_query}     = $tag_query;
    $c->stash->{all_media}     = [@all_media];
    $c->stash->{template}      = 'stats/media_tag_counts.tt2';
}

=head1 AUTHOR

,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
