package MediaWords::Controller::Search;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

use MediaWords::CM::Mine;
use MediaWords::Solr;
use MediaWords::Solr::WordCounts;
use MediaWords::Util::CSV;
use MediaWords::ActionRole::Logged;

=head1 NAME>

MediaWords::Controller::Health - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller for basic story search page

=cut

__PACKAGE__->config(
    action => {
        index => { Does => [ qw( ~Throttled ~Logged ) ] },
        wc    => { Does => [ qw( ~Throttled ~Logged ) ] },
    }
);

# number of stories to sample for the search
use constant NUM_SAMPLED_STORIES => 100;

# get tag_sets_id for collection: tag set
sub _get_collection_tag_sets_id
{
    my ( $db ) = @_;

    my $tag_set = $db->query( "select * from tag_sets where name = 'collection'" )->hash
      || die( "Unable to find 'collection' tag set" );

    return $tag_set->{ tag_sets_id };
}

# list all collection tags, with media set names attached
sub tags : Local
{
    my ( $self, $c, $tag_sets_id ) = @_;

    my $db = $c->dbis;

    $tag_sets_id //= _get_collection_tag_sets_id( $db );

    my $tag_set = $db->find_by_id( 'tag_sets', $tag_sets_id ) || die( "Unable to find tag_set '$tag_sets_id'" );

    my $tags = $db->query( <<END, $tag_sets_id )->hashes;
with set_tags as (
    
    select t.* from tags t 
        where tag_sets_id = ? and
            tags_id not in ( select tags_id from media_sets where include_in_dump = false )
            
)
        
select t.*, ms.media_set_names, mtm.media_count
    from set_tags t
    
        left join ( 
            select count(*) media_count, mtm.tags_id 
                from media_tags_map mtm
                group by mtm.tags_id
        ) mtm on ( mtm.tags_id = t.tags_id )
        
        left join (
            select ms.tags_id,
                array_to_string( array_agg( d.name || ':' || ms.name ), '; ' ) media_set_names
            from media_sets ms
                join dashboard_media_sets dms on ( dms.media_sets_id = ms.media_sets_id )
                join dashboards d on ( d.dashboards_id = dms.dashboards_id ) 
            where ms.tags_id is not null
            group by ms.tags_id
        ) ms on ( t.tags_id = ms.tags_id )

    order by media_set_names, t.tags_id
END

    $c->stash->{ tags }     = $tags;
    $c->stash->{ tag_set }  = $tag_set;
    $c->stash->{ template } = 'search/tags.tt2';
}

# list all media sources associated with the given tag
sub media : Local
{
    my ( $self, $c, $tags_id ) = @_;

    die( "no tags_id" ) unless ( $tags_id );

    my $db = $c->dbis;

    my $tag = $db->find_by_id( 'tags', $tags_id );

    my $media = $db->query( <<'END', $tags_id )->hashes;
select m.* 
    from media m join media_tags_map mtm on ( m.media_id = mtm.media_id )
    where mtm.tags_id = ?
    order by mtm.media_id
END

    $c->stash->{ media }    = $media;
    $c->stash->{ tag }      = $tag;
    $c->stash->{ template } = 'search/media.tt2';
}

# given a list of stories, generate a list of all tags with show_on_media or show_on_stories true.
# attach a comma separated list of the tags associated with each story to the story and return
# a list of story counts for each tag sorted by descending count in the following format:
# [ [ tag_name => $a, tags_id => $b, count => $c ], ... ]
sub _generate_story_tag_data
{
    my ( $db, $stories ) = @_;

    $db->begin;

    my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

    my $story_tags = $db->query( <<END )->hashes;
select distinct stm.stories_id, t.description,
        t.tags_id, coalesce( ts.label, ts.name ) || ' - ' || coalesce( t.label, t.tag ) tag_name
    from stories_tags_map stm
        join tags t on ( stm.tags_id = t.tags_id )
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where 
        stm.stories_id in ( select id from $ids_table ) and
        ( t.show_on_media or t.show_on_stories or ts.show_on_media or ts.show_on_stories )
    
union
    
select distinct s.stories_id, t.description,
        t.tags_id, coalesce( ts.label, ts.name ) || ' - ' || coalesce( t.label, t.tag ) tag_name
    from stories s
        join media_tags_map mtm on ( s.media_id = mtm.media_id )
        join tags t on ( mtm.tags_id = t.tags_id )
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where 
        s.stories_id in ( select id from $ids_table ) and
        ( t.show_on_media or t.show_on_stories or ts.show_on_media or ts.show_on_stories )

END

    $db->commit;

    my $story_tag_names  = {};
    my $story_tag_counts = {};
    for my $story_tag ( @{ $story_tags } )
    {
        push( @{ $story_tag_names->{ $story_tag->{ stories_id } } }, $story_tag->{ tag_name } );

        $story_tag_counts->{ $story_tag->{ tags_id } } //= $story_tag;
        $story_tag_counts->{ $story_tag->{ tags_id } }->{ count }++;
    }

    my $aggregate_story_tags = [
        map { { stories_id => $_, tag_names => join( "; ", @{ $story_tag_names->{ $_ } } ) } }
          keys( %{ $story_tag_names } )
    ];
    MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $aggregate_story_tags );

    return [ sort { $b->{ count } <=> $a->{ count } } values( %{ $story_tag_counts } ) ];
}

# set 'matches_pattern' field on each story
sub _match_stories_to_pattern
{
    my ( $db, $stories, $pattern ) = @_;

    $db->begin;

    my $controversy = { name => '_preview', description => '_preview', solr_seed_query => '_preview', pattern => $pattern };
    $controversy = $db->create( 'controversies', $controversy );

    map { $_->{ matches_pattern } = MediaWords::CM::Mine::story_matches_controversy_pattern( $db, $controversy, $_ ) }
      @{ $stories };

    $db->rollback;

    return $stories;
}

# stash all the parameters relevant to a wc query, which includes the 'q' param necessary for a
# non-wc search
sub _stash_wc_query_params
{
    my ( $c ) = @_;

    my $keys = MediaWords::Solr::WordCounts::get_cgi_param_attributes;

    map { $c->stash->{ $_ } = $c->req->params->{ $_ } } @{ $keys };

    if ( $c->req->params->{ languages } && ref( $c->req->params->{ languages } ) )
    {
        $c->stash->{ languages } = join( " ", @{ $c->req->params->{ languages } } );
    }
}

# if there the error is empty, return undef. if the error is a recognized message, return a
# suitable error message as the catalyst response. otherwise, print the error to stderr and
# print a generic error message
sub _return_recognized_query_error
{
    my ( $c, $error ) = @_;

    return 0 unless ( $error );

    $c->stash->{ num_stories } = 0;
    $c->stash->{ template }    = 'search/search.tt2';

    my $msg;
    if ( $error =~ /(solr.*(bad request|invalid|syntax))/i )
    {
        $c->stash->{ status_msg } = "Cannot parse search query";
    }
    elsif ( $error =~ /pseudo query error/i )
    {
        $error =~ s/at \/.*//;
        $c->stash->{ status_msg } = "Cannot parse search query: $error";
    }
    elsif ( $error =~ /throttled/i )
    {
        warn( $error );
        $c->stash->{ status_msg } = <<END;
You have exceeded your quota of requests or stories.  See your profile page at https://core.mediacloud.org/admin/profile
for your current usage and limits.  Contact info\@mediacloud.org with quota questions.
END
    }
    else
    {
        warn( $@ );
        $c->stash->{ status_msg } = 'Unknown error.  Please report to info@mediacloud.org.';
    }

    return 1;
}

# search for stories using solr and return either a sampled list of stories in html or the full list in csv
sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    my $q = $c->req->params->{ q } || '';
    my $pattern = $c->req->params->{ pattern };

    if ( !$q )
    {
        $c->stash->{ template } = 'search/search.tt2';
        $c->stash->{ title }    = 'Search';
        return;
    }

    my $db = $c->dbis;

    my $csv = $c->req->params->{ csv };

    my $solr_params = { q => $q };
    if ( $csv )
    {
        $solr_params->{ rows } = 100_000;
    }
    else
    {
        $solr_params->{ sort } = 'random_1 asc';
        $solr_params->{ rows } = NUM_SAMPLED_STORIES;
    }

    my $stories;
    eval { $stories = MediaWords::Solr::search_for_stories( $db, $solr_params ) };

    _stash_wc_query_params( $c );

    return if ( _return_recognized_query_error( $c, $@ ) );

    _match_stories_to_pattern( $db, $stories, $pattern ) if ( defined( $pattern ) );

    my $num_stories = @{ $stories };
    if ( @{ $stories } >= NUM_SAMPLED_STORIES )
    {
        $num_stories = int( MediaWords::Solr::get_last_num_found() / MediaWords::Solr::get_last_sentences_per_story() );
    }

    my $tag_counts = _generate_story_tag_data( $db, $stories );

    if ( $csv )
    {
        map { delete( $_->{ sentences } ) } @{ $stories };
        my $encoded_csv = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $stories );

        $c->response->header( "Content-Disposition" => "attachment;filename=stories.csv" );
        $c->response->content_type( 'text/csv; charset=UTF-8' );
        $c->response->content_length( bytes::length( $encoded_csv ) );
        $c->response->body( $encoded_csv );

        # number of stories + the request itself
        MediaWords::ActionRole::Logged::set_requested_items_count( $c, $num_stories + 1 );
    }
    else
    {
        $c->stash->{ stories }     = $stories;
        $c->stash->{ num_stories } = $num_stories;
        $c->stash->{ tag_counts }  = $tag_counts;
        $c->stash->{ pattern }     = $pattern;
        $c->stash->{ template }    = 'search/search.tt2';
    }
}

# print word cloud of search results
sub wc : Local
{
    my ( $self, $c ) = @_;

    my $q = $c->req->params->{ q };

    if ( !$q )
    {
        $c->stash->{ template } = 'search/wc.tt2';
        return;
    }

    if ( $q =~ /story_sentences_id|sentence_number/ )
    {
        die( "searches by sentence not allowed" );
    }

    my $wc = MediaWords::Solr::WordCounts->new( cgi_params => $c->req->params );

    my $words;
    eval { $words = $wc->get_words };

    _stash_wc_query_params( $c );

    return if ( _return_recognized_query_error( $c, $@ ) );

    if ( $c->req->params->{ csv } )
    {
        my $encoded_csv = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $words );

        $c->response->header( "Content-Disposition" => "attachment;filename=words.csv" );
        $c->response->content_type( 'text/csv; charset=UTF-8' );
        $c->response->content_length( bytes::length( $encoded_csv ) );
        $c->response->body( $encoded_csv );
    }
    else
    {
        $c->stash->{ words }    = $words;
        $c->stash->{ template } = 'search/wc.tt2';
    }
}

# print out search instructions
sub readme : Local
{
    my ( $self, $c ) = @_;

    $c->stash->{ template } = 'search/readme.tt2';
}

# list tag sets
sub tag_sets : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $tag_sets = $db->query( <<END )->hashes;
select ts.*
    from tag_sets ts
    where 
        exists ( 
            select 1 
                from media_tags_map mtm 
                    join tags t on ( mtm.tags_id = t.tags_id )
                where t.tag_sets_id = ts.tag_sets_id
        )
    order by name
END

    $c->stash->{ tag_sets } = $tag_sets;
    $c->stash->{ template } = 'search/tag_sets.tt2';
}

1;
