package MediaWords::DBI::ApiLinks;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME

MediaWords::DBI::ApiLinks - various functions related to the api_links table, used for api paging

=cut

use strict;
use warnings;

use MediaWords::Util::ParseJSON;

use Readonly;

Readonly my $DEFAULT_PAGING_LIMIT => 20;

=head1 FUNCTIONS

=cut

# look for a link associated with the parameters for this request.  if found, return; else create and return a new one.
sub __find_or_create_link($$)
{
    my ( $c, $params ) = @_;

    my $db = $c->dbis;

    my $params_copy = { %{ $params } };
    delete( $params_copy->{ key } );
    my $params_json = MediaWords::Util::ParseJSON::encode_json( $params_copy );

    my $path = $c->req->path;

    my $link = $db->query( <<SQL,
        SELECT *
        FROM api_links
        WHERE
            params_json = \$1::JSONB AND
            path = \$2
SQL
        $params_json, $path
    )->hash;

    return $link if ( $link );

    $link = { params_json => $params_json, path => $path };

    return $db->create( 'api_links', $link );
}

# if use_link_paging, set the next and previous link_id fields in the $entity->{ link_ids } hash;
sub __set_paging_links($$$$)
{
    my ( $c, $link, $entity, $entity_data_key ) = @_;

    my $link_params = MediaWords::Util::ParseJSON::decode_json( $link->{ params_json } );

    if ( $link_params->{ offset } )
    {
        my $prev_params = { %{ $link_params } };
        $prev_params->{ offset } = List::Util::max( $prev_params->{ offset } - $prev_params->{ limit }, 0 );

        my $prev_link = __find_or_create_link( $c, $prev_params );
        $entity->{ link_ids }->{ previous } = $link->{ previous_link_id } = $prev_link->{ api_links_id };
    }

    my $rows = $entity->{ $entity_data_key };

    if ( scalar( @{ $rows } ) >= $link_params->{ limit } )
    {
        my $next_params = { %{ $link_params } };
        $next_params->{ offset } += $next_params->{ limit };

        my $next_link = __find_or_create_link( $c, $next_params );
        $entity->{ link_ids }->{ next } = $link->{ next_link_id } = $next_link->{ api_links_id };
    }

    if ( $entity->{ link_ids }->{ next } || $entity->{ link_ids }->{ previous } )
    {
        $c->dbis->update_by_id( 'api_links', $link->{ api_links_id }, $link );
    }
}

# add the following links structure to the entity if $self->use_links returns true
#   { links => { current => $current_link_id, previous => $previous_link_id, next => $next_link_id }
# only add previous if $self->use_link_paging returns true and $c->req->params > 0.
# only add next if $self->use_link_paging returns trye and the number of items in
# $c->stash->{ rest }->{ $self->link_paging_key }
sub add_links_to_entity($$$)
{
    my ( $c, $entity, $entity_data_key ) = @_;

    return unless ( $c->req->method eq 'GET' );

    my $link = $c->stash->{ link } || die( "no link in stash" );

    $entity->{ link_ids }->{ current } = $link->{ api_links_id };

    __set_paging_links( $c, $link, $entity, $entity_data_key );
}

# add 'link' to the stash with a link that derefences to the current set of parameters;
# replace $c->req->params with the parameters from the link associated with $c->req->params->{ link_id } if it exists
sub process_and_stash_link($)
{
    my ( $c ) = @_;

    return unless ( $c->req->method eq 'GET' );

    my $db = $c->dbis;

    my $link_id = $c->req->params->{ link_id };

    my $link;

    if ( $link_id )
    {
        my $path = $c->req->path;
        $link = $db->query( <<SQL,
            SELECT *
            FROM api_links
            WHERE
                api_links_id = \$1 AND
                path = \$2
SQL
            $link_id, $path
        )->hash;

        die( "no such link id exists: $link_id [$path]" ) unless ( $link );

        my $link_params = MediaWords::Util::ParseJSON::decode_json( $link->{ params_json } );

        my $key = $c->req->params->{ key };

        map { delete( $c->req->params->{ $_ } ) } keys( %{ $c->req->params } );
        map { $c->req->params->{ $_ } = $link_params->{ $_ } } keys( %{ $link_params } );

        $c->req->params->{ key } = $key;
    }
    else
    {
        $c->req->params->{ limit }  ||= $DEFAULT_PAGING_LIMIT;
        $c->req->params->{ offset } ||= 0;
        $link = __find_or_create_link( $c, $c->req->params );
    }

    $c->stash->{ link } = $link;
}

1;
