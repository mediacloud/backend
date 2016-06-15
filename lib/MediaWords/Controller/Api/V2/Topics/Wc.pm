package MediaWords::Controller::Api::V2::Topics::Wc;
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

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topic_id ) = @_;
    $c->stash->{ topic_id } = $topic_id;
}

sub wc : Chained('apibase') : PathPart('wc') : CaptureArgs(0)
{

}

sub list : Chained('wc') : Args(0) : ActionClass('MC_REST')
{

}

sub list_GET
{
    my ( $self, $c ) = @_;
    my $sort_by_tfidf = $c->req->params->{ sort_by_tfidf };

    if ( $c->req->params->{ sample_size } && ( $c->req->params->{ sample_size } > 100_000 ) )
    {
        $c->req->params->{ sample_size } = 100_000;
    }
    my $cdts = MediaWords::CM::get_time_slice_for_controversy(
        $c->dbis,
        $c->stash->{ topic_id },
        $c->req->params->{ timeslice },
        $c->req->params->{ snapshot }
    );

    if ( $cdts )
    {
        my $query = "{~ controversy_dump_time_slice:$cdts->{ controversy_dump_time_slices_id } }";
        my $wc = MediaWords::Solr::WordCounts->new( { db => $c->dbis, q => $query } );

        if ( $c->req->params->{ limit } )
        {
            $wc->num_words( $c->req->params->{ limit } );
        }
        my $words = undef;
        my $stats = undef;
        if ( $c->req->params->{ include_stopwords } )
        {
            $wc->include_stopwords( 1 );
        }

        if ( $c->req->params->{ languages } )
        {
            $c->req->params->{ languages } = [ split( /[\s,]/, $c->req->params->{ languages } ) ];
            $wc->languages( $c->req->params->{ languages } );
        }
        if ( $c->req->params->{ include_stats } )
        {
            $wc->include_stats( 1 );
            my $w = $wc->get_words;
            $words = $w->{ words };
            $stats = $w->{ stats };
        }
        else
        {
            $words = $wc->get_words;
        }

        my $entity = {};
        if ( $sort_by_tfidf )
        {
            for my $word ( @{ $words } )
            {
                my $solr_df_query = "{~ controversy:$cdts->{ controversies_id } }";

                my $df = MediaWords::Solr::get_num_found(
                    $c->dbis,
                    {
                        q  => "+sentence:" . $word->{ term },
                        fq => $solr_df_query
                    }
                );

                if ( $df )
                {
                    $word->{ tfidf }       = $word->{ count } / sqrt( $df );
                    $word->{ total_count } = $df;
                }
                else
                {
                    $word->{ tfidf } = 0;
                }
            }
            $words = [ sort { $b->{ tfidf } <=> $a->{ tfidf } } @{ $words } ];
        }
        map { $words->[ $_ ]->{ rank } = $_ + 1 } ( 0 .. $#{ $words } );
        $entity->{ timeslice } = $cdts;
        $entity->{ words }     = $words;
        if ( $stats )
        {
            $entity->{ stats } = $stats;
        }
        $self->status_ok( $c, entity => $entity );
    }
    else
    {
        $self->status_bad_request( $c, message => "could not retrieve word counts" );
    }

}

1;
