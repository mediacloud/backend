package MediaWords::Solr::SentenceFieldCounts;

use Moose;

# return counts of how many sentnces match any of the following fields:
# media_id, language,

use strict;
use warnings;

use Data::Dumper;

use MediaWords::Solr;
use MediaWords::Util::Config;

# list of fields that can be queried.  the id field to return from solr.  the values from
# the id_field are joined to the tag_map_table to return tags_id counts.
my $_field_definitions = {
    tags_id_stories         => { id_field => 'stories_id',         tag_map_table => 'stories_tags_map' },
    tags_id_story_sentences => { id_field => 'story_sentences_id', tag_map_table => 'story_sentences_tags_map' }
};

# mediawords.fc_cache_version from config
my $_fc_cache_version;

# Moose instance fields

has 'q'             => ( is => 'rw', isa => 'Str' );
has 'fq'            => ( is => 'rw', isa => 'ArrayRef' );
has 'sample_size'   => ( is => 'rw', isa => 'Int', default => 1000 );
has 'field'         => ( is => 'rw', isa => 'Str', default => 'tags_id_story_sentences' );
has 'tag_sets_id'   => ( is => 'rw', isa => 'Int' );
has 'include_stats' => ( is => 'rw', isa => 'Bool' );
has 'db' => ( is => 'rw' );

# list of all attribute names that should be exposed as cgi params
sub get_cgi_param_attributes
{
    return [ qw(q fq sample_size include_stats field tag_sets_id) ];
}

# return hash of attributes for use as cgi params
sub get_cgi_param_hash
{
    my ( $self ) = @_;

    my $keys = get_cgi_param_attributes;

    my $meta = $self->meta;

    my $hash = {};
    map { $hash->{ $_ } = $meta->get_attribute( $_ )->get_value( $self ) } @{ $keys };

    return $hash;
}

# add support for constructor in this form:
#   WordsCounts->new( cgi_params => $cgi_params )
# where $cgi_params is a hash of cgi params directly from a web request
around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;

    my $args;
    if ( ref( $_[ 0 ] ) )
    {
        $args = $_[ 0 ];
    }
    elsif ( defined( $_[ 0 ] ) )
    {
        $args = { @_ };
    }
    else
    {
        $args = {};
    }

    my $vals;
    if ( $args->{ cgi_params } )
    {
        my $cgi_params = $args->{ cgi_params };

        $vals = {};
        my $keys = get_cgi_param_attributes;
        for my $key ( @{ $keys } )
        {
            $vals->{ $key } = $cgi_params->{ $key } if ( exists( $cgi_params->{ $key } ) );
        }

        $vals->{ db } = $args->{ db } if ( $args->{ db } );
    }
    else
    {
        $vals = $args;
    }

    $vals->{ fq } = [ $vals->{ fq } ] if ( $vals->{ fq } && !ref( $vals->{ fq } ) );
    $vals->{ fq } ||= [];

    return $class->$orig( $vals );
};

# given the list of ids, get the counts for the various related fields
sub _get_counts
{
    my ( $self, $ids, $field_definition ) = @_;

    my $id_field      = $field_definition->{ id_field };
    my $tag_map_table = $field_definition->{ tag_map_table };

    my $tag_set_clause = $self->tag_sets_id ? "and t.tag_sets_id = " . ( $self->tag_sets_id + 0 ) : '';

    my $ids_table = $self->db->get_temporary_ids_table( $ids );

    my $counts = $self->db->query( <<SQL )->hashes;
select
        count(*) count, t.tags_id tags_id, t.tag, t.label, t.tag_sets_id
    from $tag_map_table m
        join tags t on ( m.tags_id = t.tags_id $tag_set_clause )
    where
        m.$id_field in ( select id from $ids_table )
    group by t.tags_id
    order by count(*) desc
SQL

    return $counts;
}

# connect to solr server to get list of ss ids and then generate various counts based on those ssids
sub get_counts_from_solr_server
{
    my ( $self ) = @_;

    my $field_definition = $_field_definitions->{ $self->{ field } };
    die( "unknown field '" . $self->field . "'" ) unless ( $field_definition );

    return [] unless ( $self->q() || ( $self->fq && @{ $self->fq } ) );

    my $id_field = $field_definition->{ id_field };

    my $start_generation_time = time();

    my $solr_params = {
        q    => $self->q(),
        fq   => $self->fq,
        rows => $self->sample_size,
        fl   => $id_field,
        sort => 'random_1 asc'
    };

    my $data = MediaWords::Solr::query( $self->db, $solr_params );

    my $sentences_found = $data->{ response }->{ numFound };
    my $ids = [ map { $_->{ $id_field } } @{ $data->{ response }->{ docs } } ];

    my $counts = $self->_get_counts( $ids, $field_definition );

    if ( $self->include_stats )
    {
        return {
            stats => {
                num_sentences_returned => scalar( @{ $ids } ),
                num_sentences_found    => $sentences_found,
                sample_size_param      => $self->sample_size
            },
            counts => $counts
        };
    }
    else
    {
        return $counts;
    }
}

# return CHI cache for word counts
sub _get_cache
{
    my $mediacloud_data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

    return CHI->new(
        driver           => 'File',
        expires_in       => '1 day',
        expires_variance => '0.1',
        root_dir         => "${ mediacloud_data_dir }/cache/sentence_field_counts",
        cache_size       => '1g'
    );
}

# return key that uniquely identifies the query
sub _get_cache_key
{
    my ( $self ) = @_;

    $_fc_cache_version //= MediaWords::Util::Config->get_config->{ mediawords }->{ fc_cache_version } || '1';

    my $meta = $self->meta;

    my $keys = $self->get_cgi_param_attributes;

    my $hash_key = "$_fc_cache_version:" . Dumper( map { $meta->get_attribute( $_ )->get_value( $self ) } @{ $keys } );

    return $hash_key;
}

# get a cached value for the given word count
sub _get_cached_counts
{
    my ( $self ) = @_;

    return $self->_get_cache->get( $self->_get_cache_key );
}

# set a cached value for the given word count
sub _set_cached_counts
{
    my ( $self, $value ) = @_;

    return $self->_get_cache->set( $self->_get_cache_key, $value );
}

# perform the solr query and collect the sentence ids.  query postgres for the sentences and associated tags
# and return counts for each of the following fields:
# publish_day, media_id, language, sentence_tags_id, media_tags_id, story_tags_id
sub get_counts
{
    my ( $self ) = @_;

    my $counts = $self->_get_cached_counts;

    return $counts if ( $counts );

    $counts = $self->get_counts_from_solr_server;

    $self->_set_cached_counts( $counts );

    return $counts;
}

1;
