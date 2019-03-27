package MediaWords::Controller::Api::V2::Media;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

use Encode;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;

use MediaWords::DBI::Media::Lookup;
use MediaWords::Solr;
use MediaWords::TM::Snapshot;
use MediaWords::Util::ParseHTML;
use MediaWords::Util::Tags;
use MediaWords::Util::URL;
use MediaWords::Util::Web;

=head1 NAME

MediaWords::Controller::Media - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

__PACKAGE__->config(
    action => {
        create            => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
        put_tags          => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
        update            => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
        submit_suggestion => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        list_suggestions  => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
        mark_suggestion   => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub get_table_name
{
    return "media";
}

sub has_nested_data
{
    return 1;
}

sub _add_nested_data
{

    my ( $self, $db, $media ) = @_;

    Readonly my $single => 1;
    $media = $db->attach_child_query( $media, <<SQL, 'is_healthy', 'media_id', $single );
select m.media_id, coalesce( h.is_healthy, true ) is_healthy from media m left join media_health h using ( media_id )
SQL

    for my $field ( qw/num_stories_90 num_sentences_90/ )
    {
        $media = $db->attach_child_query( $media, <<SQL, $field, 'media_id', $single );
select m.media_id, coalesce( h.$field, 0 )::float $field from media m left join media_health h using ( media_id )
SQL
    }

    $media = $db->attach_child_query( $media, <<SQL, 'start_date', 'media_id', $single );
select m.media_id, coalesce( start_date,  now() )::date start_date from media m left join media_health h using ( media_id )
SQL

    my $media_ids_list = join( ',', map { $_->{ media_id } } @{ $media } ) || '-1';
    my $tags = $db->query( <<END )->hashes;
select mtm.media_id, t.tags_id, t.tag, t.label, t.description, mtm.tagged_date, ts.tag_sets_id, ts.name as tag_set,
        ( t.show_on_media or ts.show_on_media ) show_on_media,
        ( t.show_on_stories or ts.show_on_stories ) show_on_stories
    from media_tags_map mtm
        join tags t on ( mtm.tags_id = t.tags_id )
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    where mtm.media_id in ( $media_ids_list )
    order by t.tags_id
END

    my $tags_lookup = {};
    map { push( @{ $tags_lookup->{ $_->{ media_id } } }, $_ ) } @{ $tags };
    map { $_->{ media_source_tags } = $tags_lookup->{ $_->{ media_id } } || [] } @{ $media };

    return $media;
}

sub default_output_fields
{
    my ( $self, $c ) = @_;

    my $fields = [ qw ( name url media_id is_monitored public_notes ) ];

    push( @{ $fields }, qw ( inlink_count outlink_count story_count ) ) if ( $self->{ topic_media } );

    if ( grep { $MediaWords::DBI::Auth::Roles::List::ADMIN eq $_ } @{ $c->stash->{ api_auth }->role_names() } )
    {
        push( @{ $fields }, 'editor_notes' );
    }

    return $fields;
}

sub list_name_search_field
{
    return 'name';
}

sub order_by_clause
{
    my ( $self, $c ) = @_;

    my $sort = $c->req->params->{ sort } || 'id';

    if ( $self->{ topic_media } )
    {
        return 'inlink_count desc';
    }
    elsif ( $sort eq 'id' )
    {
        return 'media_id asc';
    }
    elsif ( $sort eq 'num_stories' )
    {
        return '( select num_stories_90 from media_health mh where mh.media_id = media.media_id ) desc nulls last';
    }
    else
    {
        die( "Unknown sort param: '$sort'" );
    }
}

# if topic_timespans_id is specified, create a temporary
# table with the media name that supercedes the normal media table
# but includes only media in the given topic timespan and
# has the topic metric data
sub _create_topic_media_table
{
    my ( $self, $c ) = @_;

    my $timespans_id = int( $c->req->params->{ timespans_id } // 0 );
    unless ( $timespans_id )
    {
        $timespans_id = int( $c->req->params->{ controversy_dump_time_slices_id } // 0 );
    }
    my $timespan_mode = $c->req->params->{ topic_mode } || $c->req->params->{ controversy_mode } || '';

    return unless ( $timespans_id );

    $self->{ topic_media } = 1;

    my $live = $timespan_mode eq 'live' ? 1 : 0;

    my $db = $c->dbis;

    my $timespan = $db->find_by_id( 'timespans', $timespans_id )
      || die( "Unable to find timespan with id '$timespans_id'" );

    my $topic = $db->query( <<END, $timespan->{ snapshots_id } )->hash;
select * from topics where topics_id in (
    select topics_id from snapshots where snapshots_id = ? )
END

    $db->begin;

    MediaWords::TM::Snapshot::setup_temporary_snapshot_views( $db, $timespan, $topic, $live );

    $db->query( <<END );
create temporary table media as
    select m.name, m.url, mlc.*
        from media m join snapshot_medium_link_counts mlc on ( m.media_id = mlc.media_id )
END

    $db->commit;
}

sub get_extra_where_clause
{
    my ( $self, $c ) = @_;

    my $clauses = [];

    my $db = $c->dbis;

    if ( my $tags_id = int( $c->req->params->{ tags_id } // 0 ) )
    {
        push( @{ $clauses },
            "and media_id in ( select mtm.media_id from media_tags_map mtm where mtm.tags_id = $tags_id )" );
    }

    if ( my $q = $c->req->params->{ q } )
    {
        my $solr_params = { q => $q };
        my $media_ids = MediaWords::Solr::search_for_media_ids( $db, $solr_params );

        $media_ids = [ map { int( $_ ) } @{ $media_ids } ];

        my $ids_table = $db->get_temporary_ids_table( $media_ids );

        push( @{ $clauses }, "and media_id in ( select id from $ids_table )" );
    }

    if ( my $tag_name = $c->req->params->{ tag_name } )
    {
        my $q_tag_name = $db->quote( '%' . lc( $tag_name ) . '%' );
        push( @{ $clauses }, <<SQL );
and media_id in (
    select media_id
        from media_tags_map mtm
            join tags t using ( tags_id )
        where
            ( t.show_on_media or t.show_on_stories ) and
            t.tag ilike $q_tag_name
)
SQL
    }

    if ( int( $c->req->params->{ unhealthy } // 0 ) )
    {
        push( @{ $clauses }, <<SQL );
and exists ( select 1 from media_health h where h.media_id = media.media_id and h.is_healthy = false )
SQL
    }

    if ( my $similar_media_id = int( $c->req->params->{ similar_media_id } // 0 ) )
    {
        # make sure this is an int
        $similar_media_id += 0;
        push( @{ $clauses }, <<SQL );
and media_id in (
    select b.media_id
        from media_tags_map a
            join media_tags_map b using ( tags_id )
        where
            a.media_id = $similar_media_id and
            a.media_id <> b.media_id
        group by b.media_id
        order by count(*) desc
        limit 100
)
SQL
    }

    if ( ( $c->req->params->{ name } || $c->req->params->{ tag_name } ) && !int( $c->req->params->{ include_dups } // 0 ) )
    {
        push( @{ $clauses }, "and dup_media_id is null" );
    }

    return @{ $clauses } ? join( "  ", @{ $clauses } ) : '';
}

sub list_GET
{
    my ( $self, $c ) = @_;

    $self->_create_topic_media_table( $c );

    return $self->SUPER::list_GET( $c );
}

# try to find a media source that matches any of the urls in the list of redirect urls for the given media source
sub _find_medium_by_response_chain
{
    my ( $db, $response ) = @_;

    while ( $response )
    {
        my $medium = MediaWords::DBI::Media::Lookup::find_medium_by_url( $db, decode( 'utf8', $response->request->url ) );
        return $medium if ( $medium );

        $response = $response->previous;
    }

    return undef;
}

# Given a list of hashes, each of which includes a 'url' key, and a response
# object, return the hash in $list for which the canonical version of the url
# is the same as the canonical version of the originally requested url for the
# response. Return undef if no match is found.
#
# This function is helpful for associating a given respone returned by
# parallel_get() with the object that originally generated the url (for
# instance, the medium input record that generate the url fetch for the medium
# title)

sub _lookup_by_response_url($$)
{
    my ( $list, $response ) = @_;

    my $url = $response->original_request->url;

    map { return ( $_ ) if ( MediaWords::Util::URL::urls_are_equal( $_->{ url }, $url ) ) } @{ $list };

    return undef;
}

# for eery record in the media/create input, attach either an existing medium or an old medium or attach
# an error record that indicates why a medium could not be created
sub _attach_media_to_input($$)
{
    my ( $db, $input_media ) = @_;

    my $fetch_urls = [];
    for my $input_medium ( @{ $input_media } )
    {
        $input_medium->{ medium } = MediaWords::DBI::Media::Lookup::find_medium_by_url( $db, $input_medium->{ url } );
        if ( $input_medium->{ medium } )
        {
            $input_medium->{ status } = 'existing';
        }
        else
        {
            if ( MediaWords::Util::URL::is_http_url( $input_medium->{ url } ) )
            {
                push( @{ $fetch_urls }, $input_medium->{ url } );
            }
            else
            {
                WARN "URL is not HTTP(s): " . $input_medium->{ url };
            }
        }
    }

    my $ua        = MediaWords::Util::Web::UserAgent->new();
    my $responses = $ua->parallel_get( $fetch_urls );

    for my $response ( @{ $responses } )
    {
        my $input_medium = _lookup_by_response_url( $input_media, $response ) || next;

        if ( !$response->is_success )
        {
            $input_medium->{ error } = "Unable to fetch medium url '$input_medium->{ url }': " . $response->status_line;
            next;
        }

        my $decoded_url = decode( 'utf8', $response->request->url );
        my $title = MediaWords::Util::ParseHTML::html_title( $response->decoded_content, $decoded_url, 128 );

        $input_medium->{ medium } = _find_medium_by_response_chain( $db, $response )
          || $db->query( "select * from media where name in ( ?, ? )", $title, $input_medium->{ name } )->hash;

        if ( $input_medium->{ medium } )
        {
            $input_medium->{ status } = 'existing';
            next;
        }

        $input_medium->{ status } = 'new';

        my $create_medium = {
            url               => $input_medium->{ url },
            name              => $input_medium->{ name } || $title,
            foreign_rss_links => normalize_boolean_for_db( $input_medium->{ foreign_rss_links } ),
            content_delay     => $input_medium->{ content_delay } || 0,
            editor_notes      => $input_medium->{ editor_notes },
            public_notes      => $input_medium->{ public_notes },
            is_monitored      => normalize_boolean_for_db( $input_medium->{ is_monitored } ),
        };
        $input_medium->{ medium } = eval { $db->create( 'media', $create_medium ) };
        $input_medium->{ error } = "Error creating medium: $@" if ( $@ );
    }

    map { $_->{ error } = "no url fetched for $_->{ url }" unless ( $_->{ medium } || $_->{ error } ) } @{ $input_media };

    my $medium_lookup = {};
    for my $input_medium ( @{ $input_media } )
    {
        my $medium = $input_medium->{ medium };
        next unless ( $medium );

        if ( my $existing_medium = $medium_lookup->{ $medium->{ media_id } } )
        {
            $input_medium->{ medium } = $existing_medium;
        }

        $medium_lookup->{ $medium->{ media_id } } = $input_medium->{ medium };
    }
}

# update each medium in $input_media:
# * add any feeds listed in $input_medium->{ feeds };
# * queue a rescrape_media job for each medium;
# * add an tags in tags_ids;
sub _apply_updates_to_media($$)
{
    my ( $db, $input_media ) = @_;

    for my $input_medium ( @{ $input_media } )
    {
        my $medium = $input_medium->{ medium };
        next unless ( $medium );

        if ( my $feeds = $input_medium->{ feeds } )
        {
            map { MediaWords::DBI::Media::add_feed_url_to_medium( $db, $input_medium->{ medium }, $_ ) } @{ $feeds };
        }

        MediaWords::JobManager::Job::add_to_queue( 'MediaWords::Job::RescrapeMedia', { media_id => $medium->{ media_id } }, undef, $db );

        if ( my $tags_ids = $input_medium->{ tags_ids } )
        {
            my $media_id = $medium->{ media_id };
            map { $db->find_or_create( 'media_tags_map', { tags_id => $_, media_id => $media_id } ) } @{ $tags_ids };
        }
    }
}

sub create : Local : ActionClass('MC_REST')
{
}

sub create_GET
{
    my ( $self, $c ) = @_;

    my $input_media = $c->req->data;

    die( "input must be a list" ) unless ( ref( $input_media ) eq ref( [] ) );

    map { die( "each record must include a 'url' field" ) unless ( $_->{ url } ) } @{ $input_media };

    map { $_->{ url } = MediaWords::Util::URL::fix_common_url_mistakes( $_->{ url } ) } @{ $input_media };

    my $db = $c->dbis;

    _attach_media_to_input( $db, $input_media );

    _apply_updates_to_media( $db, $input_media );

    my $statuses = [];
    for my $i ( @{ $input_media } )
    {
        if ( $i->{ error } )
        {
            push( @{ $statuses }, { status => 'error', error => $i->{ error }, url => $i->{ url } } );
        }
        else
        {
            push(
                @{ $statuses },
                { status => $i->{ status }, media_id => int( $i->{ medium }->{ media_id } ), url => $i->{ url } }
            );
        }
    }

    $self->status_ok( $c, entity => $statuses );
}

sub update : Local : ActionClass('MC_REST')
{
}

sub update_PUT
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    die( "input must be a hash" ) unless ( ref( $data ) eq ref( {} ) );

    die( "input must include media_id" ) unless ( $data->{ media_id } );

    my $db = $c->dbis;

    my $medium = $db->require_by_id( 'media', $data->{ media_id } );

    my $fields = [ qw/url name foreign_rss_links content_delay editor_notes public_notes is_monitored/ ];
    my $update = {};
    map { $update->{ $_ } = $data->{ $_ } if ( defined( $data->{ $_ } ) ) } @{ $fields };

    $update->{ foreign_rss_links } = normalize_boolean_for_db( $update->{ foreign_rss_links } );
    $update->{ is_monitored }      = normalize_boolean_for_db( $update->{ is_monitored } );

    $db->update_by_id( 'media', $medium->{ media_id }, $update ) if ( scalar( keys( %{ $update } ) ) > 0 );

    $self->status_ok( $c, entity => { success => 1 } );
}

sub put_tags : Local : ActionClass('MC_REST')
{
}

sub put_tags_PUT
{
    my ( $self, $c ) = @_;

    $self->process_put_tags( $c );

    $self->status_ok( $c, entity => { success => 1 } );

    return;
}

sub submit_suggestion : Local : ActionClass('MC_REST')
{
}

# submit a row to the media_suggestions table
sub submit_suggestion_GET
{
    my ( $self, $c ) = @_;

    $self->require_fields( $c, [ qw/url/ ] );

    my $data = $c->req->data;

    die( "input must be a hash" ) unless ( ref( $data ) eq ref( {} ) );

    my $db = $c->dbis;

    my $url      = $data->{ url };
    my $name     = $data->{ name } || 'none';
    my $feed_url = $data->{ feed_url } || 'none';
    my $reason   = $data->{ reason } || 'none';

    my $user = MediaWords::DBI::Auth::Info::user_info( $db, $c->user->username );
    my $auth_users_id = $user->user_id();

    $db->begin;

    my $ms = $db->create(
        'media_suggestions',
        {
            url           => $url,
            name          => $name,
            feed_url      => $feed_url,
            reason        => $reason,
            auth_users_id => $auth_users_id
        }
    );

    my $tags_ids = $data->{ tags_ids } || [];
    die( "tags_ids must be a list" ) unless ( ref( $tags_ids ) eq ref( [] ) );
    die( "each tags_id must be a postive int" ) if ( grep { $_ !~ /[0-9]+/ } @{ $tags_ids } );

    for my $tags_id ( @{ $tags_ids } )
    {
        $db->query( <<SQL, $ms->{ media_suggestions_id }, $tags_id );
insert into media_suggestions_tags_map ( media_suggestions_id, tags_id ) values ( \$1, \$2 )
SQL
    }

    $db->commit;

    $self->status_ok( $c, entity => { success => 1 } );

}

sub list_suggestions : Local : ActionClass('MC_REST')
{
}

# submit a row to the media_suggestions table
sub list_suggestions_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $tags_id = int( $c->req->params->{ tags_id } // 0 );
    my $all     = int( $c->req->params->{ all }     // 0 );

    my $clauses = [ 'true' ];

    if ( $tags_id )
    {
        push( @{ $clauses }, <<SQL );
media_suggestions_id in ( select media_suggestions_id from media_suggestions_tags_map where tags_id = $tags_id )
SQL
    }

    push( @{ $clauses }, "status = 'pending'" ) unless ( $all );

    my $clause_list = join( ' and ', @{ $clauses } );

    my $media_suggestions = $db->query( <<SQL )->hashes;
select u.email email, *
    from media_suggestions ms
        join auth_users u using ( auth_users_id )
    where $clause_list
    order by date_submitted
SQL

    $media_suggestions = $db->attach_child_query( $media_suggestions, <<SQL, 'tags_ids', 'media_suggestions_id' );
select t.tags_id, t.tag, t.label, t.description, mstm.media_suggestions_id
    from media_suggestions_tags_map mstm
        join tags t using ( tags_id )
SQL

    $self->status_ok( $c, entity => { media_suggestions => $media_suggestions } );
}

sub mark_suggestion : Local : ActionClass( 'MC_REST' )
{
}

# mark a suggestion as 'approved', 'rejected', or 'pending'
sub mark_suggestion_PUT
{
    my ( $self, $c ) = @_;

    $self->require_fields( $c, [ qw/media_suggestions_id status/ ] );

    my $data = $c->req->data;

    my $db = $c->dbis;

    my $user = MediaWords::DBI::Auth::Info::user_info( $db, $c->user->username );
    my $auth_users_id = $user->user_id();

    die( "status must be pending, approved, or rejected" )
      unless ( grep { $_ eq $data->{ status } } ( qw/pending approved rejected/ ) );

    die( "media_id required with approve" ) if ( ( $data->{ status } eq 'approved' ) && !$data->{ media_id } );

    my $ms = $db->require_by_id( 'media_suggestions', $data->{ media_suggestions_id } );

    $db->update_by_id(
        'media_suggestions',
        $data->{ media_suggestions_id },
        {
            media_suggestions_id => $data->{ media_suggestions_id },
            status               => $data->{ status },
            mark_reason          => $data->{ mark_reason },
            media_id             => $data->{ media_id },
            mark_auth_users_id   => $auth_users_id
        }
    );

    $self->status_ok( $c, entity => { success => 1 } );
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
