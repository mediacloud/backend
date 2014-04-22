package MediaWords::Controller::Admin::FacetCounts;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

use MediaWords::Solr;
use MediaWords::Util::CSV;
use MediaWords::Thrift::SolrFacets;

=head1 NAME>

MediaWords::Controller::Health - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller for basic story search page

=cut

sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    my $q = $c->req->params->{ q } || '';
    my $l = $c->req->params->{ l };

    my $facet_field = 'media_id';

    my $fq       = $c->req->params->{ fq }       || [];
    my $mincount = $c->req->params->{ mincount } || 1;

    $c->stash->{ template } = 'facet_counts/facet_counts.tt2';

    if ( !$q )
    {
        say STDERR "No q param";

        #$c->stash->{ template } = 'facet_counts/facet_counts.tt2';
        $c->stash->{ title } = 'Facet Counts';
        return;
    }

    say STDERR "q= $q";

    $c->stash->{ q } = $q;

    my $db = $c->dbis;

    my $csv = $c->req->params->{ csv };

    my $num_sampled = $csv ? undef : 1000;

    my $counts = MediaWords::Thrift::SolrFacets::get_media_counts( $q, $facet_field, $fq, $mincount );

    #say STDERR Dumper( $counts );

    my $media_ids = [ sort { $a <=> $b } keys %{ $counts } ];
    my $count_list = [ map { { media_id => $_, count => $counts->{ $_ } } } @{ $media_ids } ];

    if ( $csv )
    {

        my $encoded_csv = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $count_list, [ qw ( media_id count ) ] );

        $c->response->header( "Content-Disposition" => "attachment;filename=counts.csv" );
        $c->response->content_type( 'text/csv; charset=UTF-8' );
        $c->response->content_length( bytes::length( $encoded_csv ) );
        $c->response->body( $encoded_csv );
    }
    else
    {
        $c->stash->{ counts } = $count_list;

        #$c->stash->{ template }    = 'facet_count/facet_counts.tt2';
    }
}

1;
