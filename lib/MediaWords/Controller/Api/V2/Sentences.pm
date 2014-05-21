package MediaWords::Controller::Api::V2::Sentences;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::StorySubsets;
use strict;
use warnings;
use base 'Catalyst::Controller';
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Carp;
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

__PACKAGE__->config( action_roles => [ 'NonPublicApiKeyAuthenticated' ], );

use MediaWords::Tagger;

sub get_table_name
{
    return "story_sentences";
}

sub list : Local : ActionClass('REST') : Does('~NonPublicApiKeyAuthenticated') : Does('~Throttled') : Does('~Logged')
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

# attach the following fields to each sentence: sentence_number, media_id, publish_date
sub _attach_data_to_sentences
{
    my ( $db, $sentences ) = @_;

    return unless ( @{ $sentences } );

    my $temp_ss_ids = _get_ss_ids_temporary_table( $db, $sentences );

    my $story_sentences = $db->query( <<END )->hashes;
select ss.story_sentences_id, ss.sentence_number, ss.media_id, ss.publish_date
    from story_sentences ss
        join $temp_ss_ids q on ( ss.story_sentences_id = q.story_sentences_id )
END

    $db->query( "drop table $temp_ss_ids" );

    my $ss_lookup = {};
    map { $ss_lookup->{ $_->{ story_sentences_id } } = $_ } @{ $story_sentences };

    for my $sentence ( @{ $sentences } )
    {
        my $ss_data = $ss_lookup->{ $sentence->{ story_sentences_id } };
        map { $sentence->{ $_ } = $ss_data->{ $_ } } qw/sentence_number media_id publish_date/;
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

    my $list = MediaWords::Solr::query( $params );

    #say STDERR "Got List:\n" . Dumper( $list );

    my $sentences = $list->{ response }->{ docs };

    _attach_data_to_sentences( $c->dbis, $sentences );

    $self->status_ok( $c, entity => $list );
}

sub count : Local : ActionClass('REST') : Does('~PublicApiKeyAuthenticated') : Does('~Throttled') : Does('~Logged')
{
}

sub count_GET : Local
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
    $params->{ rows }  = 0;

    #$params->{ sort } = _get_sort_param( $sort ) if ( $rows );

    $rows = List::Util::min( $rows, 10000 );

    my $list = MediaWords::Solr::query( $params );

    my $count = $list->{ response }->{ numFound };

    #_attach_data_to_sentences( $c->dbis, $sentences );

    $self->status_ok( $c, entity => { count => $count } );
}

##TODO merge with stories put_tags
sub put_tags : Local : Does('~NonPublicApiKeyAuthenticated') : Does('~Throttled') : Does('~Logged')
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
