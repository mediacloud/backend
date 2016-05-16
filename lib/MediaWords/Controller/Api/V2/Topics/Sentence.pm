package MediaWords::Controller::Api::V2::Topics::Sentence;
use Modern::Perl "2015";
use MediaWords::CommonLibs;
use Data::Dumper;
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
use MediaWords::CM::Dump;
use MediaWords::CM;
use MediaWords::Controller::Api::V2::Sentences;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { count_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topic_id ) = @_;
    $c->stash->{ topic_id } = $topic_id;
}

sub sentence : Chained('apibase') : PathPart('sentence') : CaptureArgs(0)
{

}

sub count : Chained('sentence') : Args(0) : ActionClass('REST')
{

}

sub count_GET
{
    my ( $self, $c ) = @_;
    my $entity = {};
    my $q      = $c->req->params->{ 'q' };
    my $fq     = $c->req->params->{ 'fq' };
    if ( $q )
    {
        my $cdts = MediaWords::CM::get_time_slice_for_controversy(
            $c->dbis,
            $c->stash->{ topic_id },
            $c->req->params->{ timeslice },
            $c->req->params->{ snapshot }
        );
        my $solr_df_query = "{~ controversy:$cdts->{ controversies_id } }";
        my $composed_fq = $fq ? $solr_df_query . " AND $fq" : $solr_df_query;
        $c->req->params->{ 'fq' } = $composed_fq;
        my $split = $c->req->params->{ 'split' };
        my $response;
        if ( $split )
        {
            $response->{ split }->{ counts } = [];
            $response = MediaWords::Controller::Api::V2::Sentences::_get_count_with_split( $self, $c );
            foreach my $key ( sort keys %{ $response->{ split } } )
            {
                if ( $key =~ /^\d\d\d\d/ )
                {
                    my $data = { date => $key, count => $response->{ split }->{ $key } };
                    push @{ $response->{ split }->{ counts } }, $data;
                    delete $response->{ split }->{ $key };
                }
            }
        }
        else
        {
            my $list = MediaWords::Solr::query( $c->dbis, { q => $q, fq => $composed_fq }, $c );
            $response = { count => $list->{ response }->{ numFound } };
        }

        # my $response = MediaWords::Solr::query( $c->dbis, { q => $q, fq => $composed_fq }, $c );
        #
        # $response = { count => $response->{ response }->{ numFound } };
        $self->status_ok( $c, entity => $response );

    }
    else
    {
        $self->status_bad_request( $c, message => "Did not provide required q parameter" );
    }
}

1;
