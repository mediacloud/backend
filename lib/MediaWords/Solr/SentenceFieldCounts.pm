package MediaWords::Solr::SentenceFieldCounts;

use Moose;

# get a sample of ss ids for the given query

use strict;
use warnings;

use Data::Dumper;
use Encode;
use Getopt::Long;
use HTTP::Request::Common;
use HTTP::Server::Simple::CGI;
use IO::Socket::INET;
use JSON;
use LWP::UserAgent;
use Lingua::Stem::Snowball;
use List::Util;
use URI::Escape;

use MediaWords::Solr;
use MediaWords::Util::Config;

# mediawords.fc_cache_version from config
my $_fc_cache_version;

# Moose instance fields

has 'q'             => ( is => 'rw', isa => 'Str' );
has 'fq'            => ( is => 'rw', isa => 'ArrayRef' );
has 'sample_size'   => ( is => 'rw', isa => 'Int', default => 1000 );
has 'include_stats' => ( is => 'rw', isa => 'Bool' );
has 'db' => ( is => 'rw' );

# list of all attribute names that should be exposed as cgi params
sub get_cgi_param_attributes
{
    return [ qw(q fq sample_size include_stats) ];
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

# given the list of ssids, get the counts for the various related fields
sub _get_counts
{
    my ( $self, $ss_ids ) = @_;

    my $ids_table = $self->db->get_temporary_ids_table( $ss_ids );

    my $story_sentences = $self->db->query( <<END )->hashes;
select ss.media_id, coalesce( ss.language, 'none' ) lang, date_trunc( 'day', ss.publish_date ) publish_day 
    from stories ss 
    where ss.stories_id in ( select id from $ids_table )
END

    my $counts = {};
    for my $ss ( @{ $story_sentences } )
    {
        map { $counts->{ $_ }->{ $ss->{ $_ } }++ } qw(media_id publish_day lang);
    }

    return $counts;
}

# connect to solr server to get list of ss ids and then generate various counts based on those ssids
sub get_counts_from_solr_server
{
    my ( $self ) = @_;

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
    my $ss_ids = [ map { $_->{ stories_id } } @{ $data->{ response }->{ docs } } ];

    my $counts = $self->_get_counts( $ss_ids );

    if ( $self->include_stats )
    {
        return {
            stats => {
                num_sentences_returned => scalar( @{ $ss_ids } ),
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
