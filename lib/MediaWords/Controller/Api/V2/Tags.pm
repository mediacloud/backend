package MediaWords::Controller::Api::V2::Tags;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;
use MediaWords::DBI::StorySubsets;
use MediaWords::Controller::Api::V2::MC_REST_SimpleObject;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

sub get_name_search_clause
{
    my ( $self, $c ) = @_;

    my $v = $c->req->params->{ search };

    return '' unless ( $v );

    return 'and false' unless ( length( $v ) > 2 );

    my $qv = $c->dbis->dbh->quote( $v );

    return <<END;
and tags_id in ( 
    select t.tags_id 
        from tags t 
            join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
        where 
            ( t.tag || ' ' || t.label || ' ' || ts.name || ' ' || ts.label ) ilike '%' || $qv || '%'
)
END
}

sub get_table_name
{
    return "tags";
}

sub list_optional_query_filter_field
{
    return 'tag_sets_id';
}

sub _fetch_list
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    my $public = $c->req->params->{ public } || '';
    $public = $public eq '1' ? 1 : 0;

    if ( $public )
    {
        $c->dbis->query( <<END );
create temporary view tags as
    select t.tags_id, t.tag_sets_id, t.label, t.description, 
        t.show_on_media OR ts.show_on_media show_on_media,
        t.show_on_stories OR ts.show_on_stories show_on_stories
    from tags t
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where 
        t.show_on_media or ts.show_on_media or t.show_on_stories or ts.show_on_stories
END
    }

    return MediaWords::Controller::Api::V2::MC_REST_SimpleObject::_fetch_list( @_ );
}

1;
