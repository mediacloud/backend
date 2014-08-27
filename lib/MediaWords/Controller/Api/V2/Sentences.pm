package MediaWords::Controller::Api::V2::Sentences;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::StorySubsets;
use strict;
use warnings;
use base 'Catalyst::Controller';

use Carp;
use Date::Calc;
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;

use MediaWords::Solr;

=head1 NAME

MediaWords::Controller::Media - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

__PACKAGE__->config(    #
    action => {         #
        single_GET => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] }
        ,               # overrides "MC_REST_SimpleObject"
        list_GET => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] }
        ,               # overrides "MC_REST_SimpleObject"
        put_tags_PUT => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] },    #
        count_GET    => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },       #
      }    #
);         #

use MediaWords::Tagger;

sub get_table_name
{
    return "story_sentences";
}

sub list : Local : ActionClass('REST')
{
    #say STDERR "starting Sentences/list";
}

# fill ss_ids temporary table with story_sentence_ids from the given sentences
# and return the temp table name
sub _get_ss_ids_temporary_table
{
    my ( $db, $sentences ) = @_;

    $db->query( "create temporary table _ss_ids ( story_sentences_id bigint )" );

    eval { $db->dbh->do( "copy _ss_ids from STDIN" ) };
    die( " Error on copy for _ss_ids: $@" ) if ( $@ );

    for my $ss ( @{ $sentences } )
    {
        eval { $db->dbh->pg_putcopydata( "$ss->{ story_sentences_id }\n" ); };
        die( " Error on pg_putcopydata for _ss_ids: $@" ) if ( $@ );
    }

    eval { $db->dbh->pg_putcopyend(); };

    die( " Error on pg_putcopyend for _ss_ids: $@" ) if ( $@ );

    return '_ss_ids';
}

# attach the following fields to each sentence: sentence_number, media_id, publish_date, url, medium_name
sub _attach_data_to_sentences
{
    my ( $db, $sentences ) = @_;

    return unless ( @{ $sentences } );

    my $temp_ss_ids = _get_ss_ids_temporary_table( $db, $sentences );

    my $story_sentences = $db->query( <<END )->hashes;
select ss.story_sentences_id, ss.sentence_number, ss.media_id, ss.publish_date,
        s.url, m.name medium_name
    from story_sentences ss
        join $temp_ss_ids q on ( ss.story_sentences_id = q.story_sentences_id )
        join stories s on ( s.stories_id = ss.stories_id )
        join media m on ( ss.media_id = m.media_id )
END

    $db->query( "drop table $temp_ss_ids" );

    my $ss_lookup = {};
    map { $ss_lookup->{ $_->{ story_sentences_id } } = $_ } @{ $story_sentences };

    for my $sentence ( @{ $sentences } )
    {
        my $ss_data = $ss_lookup->{ $sentence->{ story_sentences_id } };
        map { $sentence->{ $_ } = $ss_data->{ $_ } } qw/sentence_number media_id publish_date url medium_name/;
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

sub list_GET : Local
{
    my ( $self, $c ) = @_;

    # say STDERR "starting list_GET";

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

    #say STDERR "Got List:\n" . Dumper( $list );

    my $sentences = $list->{ response }->{ docs };

    _attach_data_to_sentences( $c->dbis, $sentences );

    $self->status_ok( $c, entity => $list );
}

sub count : Local : ActionClass('REST')
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
    elsif ( $days < 15 )   { $facet_date_gap = '+1DAY' }
    elsif ( $days < 45 )   { $facet_date_gap = '+3DAYS' }
    elsif ( $days < 105 )  { $facet_date_gap = '+7DAYS' }
    else                   { $facet_date_gap = '+1MONTH' }

    my $params;
    $params->{ q }                  = $q;
    $params->{ fq }                 = $fq;
    $params->{ facet }              = 'true';
    $params->{ 'facet.date' }       = 'publish_date';
    $params->{ 'facet.date.gap' }   = $facet_date_gap;
    $params->{ 'facet.date.start' } = "${ start_date }T00:00:00Z";
    $params->{ 'facet.date.end' }   = "${ end_date }T00:00:00Z";

    my $solr_response = MediaWords::Solr::query( $c->dbis, $params, $c );

    return {
        count => $solr_response->{ response }->{ numFound },
        split => $solr_response->{ facet_counts }->{ facet_dates }->{ publish_date },
    };
}

sub count_GET : Local
{
    my ( $self, $c ) = @_;

    # say STDERR "starting list_GET";

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

##TODO merge with stories put_tags
sub put_tags : Local : ActionClass('REST')
{
}

sub put_tags_PUT : Local
{
    my ( $self, $c ) = @_;
    my $subset = $c->req->data;

    my $story_tag = $c->req->params->{ 'sentence_tag' };

    my $story_tags;

    if ( ref $story_tag )
    {
        $story_tags = $story_tag;
    }
    else
    {
        $story_tags = [ $story_tag ];
    }

    say STDERR Dumper( $story_tags );

    $self->_add_tags( $c, $story_tags );

    $self->status_ok( $c, entity => $story_tags );

    return;
}

1;
