package MediaWords::Controller::Stats_static;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;
use warnings;
use parent 'Catalyst::Controller';

use URI::Escape;
use DBIx::Simple;

sub index : Path : Args(0)
{

    return media_tag_counts( @_ );
}

# get the url of a chart image for the given tag counts
sub get_tag_count_chart_url
{
    my ( $self, $c, $query_result, $title ) = @_;

    my @media_tags = $query_result->hashes();

    if ( @media_tags == 0 )
    {
        return "";
    }

    my $max_tag_count = $media_tags[ 0 ]->{ 'media_tag_count' };

    my $data = "";
    foreach my $tag_count_row ( @media_tags )
    {
        if ( $data ne "" )
        {
            $data = $data . ',';
        }
        $data .= ( ( $tag_count_row->{ 'media_tag_count' } / $max_tag_count ) * 100 );
    }

    my $tags = join( '|', reverse map { uri_escape( $_->{ 'tag_name' } ) } @media_tags );
    my $esc_title = uri_escape( $title );

    my $url = "http://chart.apis.google.com/chart?cht=bhs&chs=350x300&chd=t:$data&chxt=y&chxl=0:|$tags&chtt=$esc_title";
}

# generate and stash the medium, media_tag_counts, and chart_url template
# for the given num
sub stash_media_tag_counts
{
    my ( $self, $c, $use_countries, $tag_sets_id, $num ) = @_;

    my $media_id = $c->request->param( 'media_id_' . $num );

    if ( !$media_id )
    {
        return;
    }

    if ( $media_id !~ /^\d+$/ )
    {
        die( "Invalid medium $media_id" );
    }

    my $media_name = $self->get_media_id_value_map( $c )->{ $media_id };

    if ( !defined( $media_name ) )
    {
        die( "Unable to find medium $media_id" );
    }

    my $result = $c->dbis->query(
        "select tags_id, media_tag_count, tag_name from top_ten_tags_for_media " .
          "where media_id=? and tag_sets_id = ? limit 10",
        $media_id, $tag_sets_id
    );

    my $chart_url = $self->get_tag_count_chart_url( $c, $result, $media_name );

    $c->stash->{ media_id }->{ $num }   = $media_id;
    $c->stash->{ media_name }->{ $num } = $media_name;
    $c->stash->{ chart_url }->{ $num }  = $chart_url;
}

sub get_media_id_value_map
{
    my ( $self, $c ) = @_;

    BEGIN
    {
        my %media_id_value_map;

        sub get_all_media_ref
        {
            my ( $self, $c ) = @_;
            if ( !%media_id_value_map )
            {
                my $result = $c->dbis->query( "select media_id, name from media" );

                %media_id_value_map = $result->flat();
            }
            return \%media_id_value_map;
        }
    }
    return get_all_media_ref( $self, $c );
}

sub get_NYTTopics_tag_sets_id
{
    my ( $self, $c ) = @_;

    BEGIN
    {
        my $nyt_topics_tag_sets_id;

        sub get_NYTopics_tag_id_ref
        {
            my ( $c ) = @_;
            if ( !defined( $nyt_topics_tag_sets_id ) )
            {
                ( $nyt_topics_tag_sets_id ) =
                  $c->dbis->query( "select tag_sets_id from tag_sets where name = 'NYTTopics'" )->flat;
            }
            return \$nyt_topics_tag_sets_id;
        }
    }

    return get_NYTopics_tag_id_ref( $c );

}

sub get_Calais_tag_sets_id
{
    my ( $self, $c ) = @_;

    BEGIN
    {
        my $calais_tag_sets_id;

        sub get_calais_tag_sets_id_ref
        {
            my ( $c ) = @_;
            if ( !defined( $calais_tag_sets_id ) )
            {
                ( $calais_tag_sets_id ) = $c->dbis->query( "select tag_sets_id from tag_sets where name = 'Calais'" )->flat;
            }
            return \$calais_tag_sets_id;
        }
    }

    return get_calais_tag_sets_id_ref( $c );

}

# return the top ten tags for the given medium
sub media_tag_counts : Local
{
    my ( $self, $c ) = @_;

    my $use_countries;
    my $tags        = [];
    my $tag_sets_id = $c->request->param( 'tag_sets_id' );

    $tag_sets_id ||= ${ $self->get_Calais_tag_sets_id( $c ) };

    for my $i ( 1 .. 3 )
    {
        $self->stash_media_tag_counts( $c, $use_countries, $tag_sets_id, $i );
    }

    # increase from 1000 to handle all media_tag_counts
    $Template::Directive::WHILE_MAX = 2000;

    $c->stash->{ template } = 'stats/media_tag_counts_simple.tt2';
}

=head1 AUTHOR

,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
