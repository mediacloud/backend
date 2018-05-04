package MediaWords::Solr::SentenceFieldCounts;

use Moose;

# return counts of how many sentences match any of the following fields:
# media_id, language,

use strict;
use warnings;

use CHI;
use Data::Dumper;

use MediaWords::Solr;
use MediaWords::Util::Config;

# list of fields that can be queried.  the id field to return from solr.  the values from
# the id_field are joined to the tag_map_table to return tags_id counts.
my $_field_definitions = { tags_id_stories => { id_field => 'stories_id', tag_map_table => 'stories_tags_map' }, };

# Moose instance fields

has 'q'             => ( is => 'rw', isa => 'Str' );
has 'fq'            => ( is => 'rw', isa => 'ArrayRef' );
has 'sample_size'   => ( is => 'rw', isa => 'Int', default => 1000 );
has 'field'         => ( is => 'rw', isa => 'Str', default => 'tags_id_stories' );
has 'tag_sets_id'   => ( is => 'rw', isa => 'Int' );
has 'include_stats' => ( is => 'rw', isa => 'Bool' );
has 'db' => ( is => 'rw' );

# list of all attribute names that should be exposed as cgi params
sub _get_cgi_param_attributes()
{
    return [ qw(q fq sample_size include_stats field tag_sets_id) ];
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
        my $keys = _get_cgi_param_attributes();
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
sub _get_postgresql_counts
{
    my ( $self, $ids, $field_definition ) = @_;

    my $id_field      = $field_definition->{ id_field };
    my $tag_map_table = $field_definition->{ tag_map_table };

    my $tag_set_clause = $self->tag_sets_id ? "and t.tag_sets_id = " . ( $self->tag_sets_id + 0 ) : '';

    $ids = [ map { int( $_ ) } @{ $ids } ];

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

# perform the solr query and collect the sentence ids.  query postgres for the sentences and associated tags
# and return counts for each of the following fields:
# publish_day, media_id, language, sentence_tags_id, media_tags_id, story_tags_id
sub get_counts
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
    my $ids = [ map { int( $_->{ $id_field } ) } @{ $data->{ response }->{ docs } } ];

    my $counts = $self->_get_postgresql_counts( $ids, $field_definition );

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

1;
