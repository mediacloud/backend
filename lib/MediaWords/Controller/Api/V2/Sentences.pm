package MediaWords::Controller::Api::V2::Sentences;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

use Date::Calc;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;

use MediaWords::Solr;
use MediaWords::Solr::SentenceFieldCounts;

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
        single      => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        list        => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        count       => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        field_count => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub get_table_name
{
    return "story_sentences";
}

sub list : Local : ActionClass('MC_REST')
{
    #TRACE "starting Sentences/list";
}

# fill stories_ids temporary table with stories_ids from the given sentences
# and return the temp table name
sub _get_stories_ids_temporary_table
{
    my ( $db, $sentences ) = @_;

    my $table_name = '_stories_ids';

    $db->query( "CREATE TEMPORARY TABLE $table_name (stories_id BIGINT)" );

    my $copy_from = $db->copy_from( "COPY $table_name FROM STDIN" );
    for my $ss ( @{ $sentences } )
    {
        $copy_from->put_line( $ss->{ stories_id } . '' );
    }
    $copy_from->end();

    return $table_name;
}

# attach the following fields to each sentence:
# sentence_number, media_id, publish_date, url, medium_name, sentence, language
sub _attach_data_to_sentences
{
    my ( $db, $sentences ) = @_;

    return unless ( $sentences && @{ $sentences } );

    my $story_sentences_ids = [ map { int( $_->{ story_sentences_id } ) } @{ $sentences } ];
    my $temp_ss_ids         = $db->get_temporary_ids_table( $story_sentences_ids );
    my $story_sentences     = $db->query( <<SQL )->hashes;
select
        s.publish_date, s.stories_id, s.url, m.name medium_name, s.media_id,
        ss.story_sentences_id, ss.sentence, ss.language, ss,sentence_number
    from story_sentences ss
        join stories s using ( stories_id )
        join media m on ( s.media_id = m.media_id )
    where
        story_sentences_id in ( select id from $temp_ss_ids )
SQL

    my $ss_lookup = {};
    map { $ss_lookup->{ int( $_->{ story_sentences_id } ) } = $_ } @{ $story_sentences };

    for my $sentence ( @{ $sentences } )
    {
        my $ss     = $ss_lookup->{ int( $sentence->{ story_sentences_id } ) };
        my $fields = [ keys( %{ $ss } ) ];
        map { $sentence->{ $_ } = $ss->{ $_ } } keys( %{ $ss } );
    }
}

# return the solr sort param corresponding with the possible
# api params values of publish_date_asc, publish_date_desc, and random
sub _get_sort_param
{
    my ( $sort ) = @_;

    $sort //= 'publish_date_asc';

    $sort = lc( $sort );

    if ( $sort eq 'publish_date_asc' )
    {
        return 'publish_date asc';
    }
    elsif ( $sort eq 'publish_date_desc' )
    {
        return 'publish_date desc';
    }
    elsif ( $sort eq 'random' )
    {
        return 'random_1 asc';
    }
    else
    {
        die( "Unknown sort: $sort" );
    }
}

# given the raw data structure returned by the solr query to sentences/list, return the entity that should be passed
# back to the client for the sentences/list end point.  this is mostly just mirroring the solr data structure, but
# we include it so that we don't pass extra fields that may pop up in the solr query over time as we change sorl versions
# and schemas.
sub _get_sentences_entity_from_json_data
{
    my ( $data ) = @_;

    my $entity = {};

    map { $entity->{ responseHeader }->{ params }->{ $_ } = $data->{ responseHeader }->{ params }->{ $_ } }
      qw/sort df wt q fq rows start/;

    map { $entity->{ responseHeader }->{ $_ } = $data->{ responseHeader }->{ $_ } } qw/status QTime/;

    $entity->{ response }->{ numFound } = $data->{ response }->{ numFound };

    for my $data_doc ( @{ $data->{ response }->{ docs } } )
    {
        my $entity_doc = {};

        map { $entity_doc->{ $_ } = $data_doc->{ $_ } }
          qw/sentence media_id publish_date sentence_number stories_id story_sentences_id _version_/;

        push( @{ $entity->{ response }->{ docs } }, $entity_doc );
    }

    return $entity;
}

sub list_GET
{
    my ( $self, $c ) = @_;

    # TRACE "starting list_GET";

    my $params = {};

    my $q  = $c->req->params->{ 'q' };
    my $fq = $c->req->params->{ 'fq' };

    my $start = $c->req->params->{ 'start' };
    my $rows  = $c->req->params->{ 'rows' };
    my $sort  = $c->req->params->{ 'sort' };

    $rows  //= 1000;
    $start //= 0;

    $params->{ q }     = $q;
    $params->{ fq }    = $fq;
    $params->{ start } = $start;
    $params->{ rows }  = $rows;

    $params->{ sort } = _get_sort_param( $sort ) if ( $rows );

    $rows = List::Util::min( $rows, 10000 );

    my $list = MediaWords::Solr::query( $c->dbis, $params, $c );

    my $entity = _get_sentences_entity_from_json_data( $list );

    my $sentences = $entity->{ response }->{ docs };

    _attach_data_to_sentences( $c->dbis, $sentences );

    MediaWords::Util::JSON::numify_fields( $sentences, [ qw/stories_id story_sentences_id/ ] );
    MediaWords::Util::JSON::numify_fields( [ $entity->{ responseHeader }->{ params } ], [ qw/rows start/ ] );

    $self->status_ok( $c, entity => $entity );
}

sub count : Local : ActionClass('MC_REST')
{
}

# get the overall count for the given query, plus a split of counts divided by
# date ranges.  The date range is either daily, every 3 days, weekly, or monthly
# depending on the number of total days in the query
sub _get_count_with_split
{
    my ( $self, $c ) = @_;

    my $q           = $c->req->params->{ 'q' };
    my $fq          = $c->req->params->{ 'fq' };
    my $start_date  = $c->req->params->{ 'split_start_date' };
    my $end_date    = $c->req->params->{ 'split_end_date' };
    my $split_daily = $c->req->params->{ 'split_daily' };

    die( "must include split_start_date and split_end_date of split is true" ) unless ( $start_date && $end_date );

    die( "split_start_date must be in the format YYYY-MM-DD" ) unless ( $start_date =~ /(\d\d\d\d)-(\d\d)-(\d\d)/ );
    my ( $sdy, $sdm, $sdd ) = ( $1, $2, $3 );

    die( "split_end_date must be in the format YYYY-MM-DD" ) unless ( $end_date =~ /(\d\d\d\d)-(\d\d)-(\d\d)/ );
    my ( $edy, $edm, $edd ) = ( $1, $2, $3 );

    my $days = Date::Calc::Delta_Days( $sdy, $sdm, $sdd, $edy, $edm, $edd );

    my $facet_date_gap;

    if    ( $split_daily ) { $facet_date_gap = '+1DAY' }
    elsif ( $days < 90 )   { $facet_date_gap = '+1DAY' }
    elsif ( $days < 180 )  { $facet_date_gap = '+3DAYS' }
    else                   { $facet_date_gap = '+7DAYS' }

    my $params;
    $params->{ q }                   = $q;
    $params->{ fq }                  = $fq;
    $params->{ facet }               = 'true';
    $params->{ 'facet.range' }       = 'publish_day';
    $params->{ 'facet.range.gap' }   = $facet_date_gap;
    $params->{ 'facet.range.start' } = "${ start_date }T00:00:00Z";
    $params->{ 'facet.range.end' }   = "${ end_date }T00:00:00Z";

    my $solr_response = MediaWords::Solr::query( $c->dbis, $params, $c );

    my $count        = $solr_response->{ response }->{ numFound } + 0;
    my $facet_counts = $solr_response->{ facet_counts }->{ facet_ranges }->{ publish_day };

    unless ( scalar( @{ $facet_counts->{ 'counts' } } ) % 2 == 0 )
    {
        die "Number of elements in 'counts' is not even.";
    }

    my %split = (
        'start' => $facet_counts->{ 'start' },
        'end'   => $facet_counts->{ 'end' },
        'gap'   => $facet_counts->{ 'gap' },
    );

    # Remake array into date => count hashref
    my %hash_counts = @{ $facet_counts->{ 'counts' } };
    %split = ( %split, %hash_counts );

    return { count => $count, split => \%split };
}

sub count_GET
{
    my ( $self, $c ) = @_;

    # TRACE "starting list_GET";

    my $params = {};

    my $q     = $c->req->params->{ 'q' };
    my $fq    = $c->req->params->{ 'fq' };
    my $split = $c->req->params->{ 'split' };

    my $response;
    if ( $split )
    {
        $response = $self->_get_count_with_split( $c, $params );
    }
    else
    {
        my $list = MediaWords::Solr::query( $c->dbis, { q => $q, fq => $fq }, $c );
        $response = { count => $list->{ response }->{ numFound } };
    }

    $self->status_ok( $c, entity => $response );
}

sub field_count : Local : ActionClass('MC_REST')
{
}

sub field_count_GET
{
    my ( $self, $c ) = @_;

    my $db     = $c->dbis;
    my $params = $c->req->params;

    my $counts = MediaWords::Solr::SentenceFieldCounts::get_counts(
        $db,                           #
        $params->{ q },                #
        $params->{ fq },               #
        $params->{ sample_size },      #
        $params->{ tag_sets_id },      #
        $params->{ include_stats },    #
    );

    $self->status_ok( $c, entity => $counts );
}

# override
sub single_GET
{
    die( "not implemented" );
}

1;
