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
    my ( $self, $ids ) = @_;

    my $tag_set_clause = $self->tag_sets_id ? "AND t.tag_sets_id = " . ( $self->tag_sets_id + 0 ) : '';

    $ids = [ map { int( $_ ) } @{ $ids } ];

    my $ids_table = $self->db->get_temporary_ids_table( $ids );

    my $counts = $self->db->query( <<SQL )->hashes;
        SELECT
            COUNT(*) AS count,
            t.tags_id AS tags_id,
            t.tag,
            t.label,
            t.tag_sets_id
        FROM stories_tags_map AS m
            JOIN tags AS t ON (
                m.tags_id = t.tags_id
                $tag_set_clause
            )
        WHERE m.stories_id IN (
            SELECT id
            FROM $ids_table
        )
        GROUP BY t.tags_id
        ORDER BY COUNT(*) DESC
SQL

    return $counts;
}

# perform the solr query and collect the sentence ids.  query postgres for the sentences and associated tags
# and return counts for each of the following fields:
# publish_day, media_id, language, sentence_tags_id, media_tags_id, story_tags_id
sub get_counts
{
    my ( $self ) = @_;

    unless ( $self->{ field } eq 'tags_id_stories' )
    {
        die "Unknown field: " . $self->{ field };
    }

    return [] unless ( $self->q() || ( $self->fq && @{ $self->fq } ) );

    my $start_generation_time = time();

    my $solr_params = {
        q    => $self->q(),
        fq   => $self->fq,
        rows => $self->sample_size,
        fl   => 'stories_id',
        sort => 'random_1 asc'
    };

    my $data = MediaWords::Solr::query( $self->db, $solr_params );

    my $sentences_found = $data->{ response }->{ numFound };
    my $ids = [ map { int( $_->{ 'stories_id' } ) } @{ $data->{ response }->{ docs } } ];

    my $counts = $self->_get_postgresql_counts( $ids );

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
