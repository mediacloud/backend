package MediaWords::Controller::Api::V2::ExtractLines;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::StorySubsets;
use strict;
use warnings;
use base 'Catalyst::Controller::REST';
use JSON;
use Encode;
use utf8;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Carp;

=head1 NAME

MediaWords::Controller::Api::V2::ExtractLines - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

# Default authentication action roles
__PACKAGE__->config(    #
    action => {         #
        story_lines_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },    #
      }    #
);         #

use constant ROWS_PER_PAGE => 20;

use MediaWords::Tagger;

sub story_lines : Local : ActionClass('REST')
{
}

sub story_lines_GET : Local
{
    my ( $self, $c ) = @_;
    my $body_html = $c->req->param( 'body_html' );
    $body_html //= ROWS_PER_PAGE;

    # say STDERR "rows $rows";

    my $lines = [ split( /[\n\r]+/, $body_html ) ];

    $lines = MediaWords::Crawler::Extractor::preprocess( $lines );

    $self->status_ok( $c, entity => $lines );
}

sub extract : Local : ActionClass('REST')    # action roles are to be set for each derivative sub-actions
{
}

sub extract_GET : Local
{
    my ( $self, $c ) = @_;

    my $temp               = $c->req->param( 'preprocessed_lines' );
    my $pp_lines           = encode_utf8( $temp );
    my $preprocessed_lines = decode_json( $pp_lines );
    my $story_title        = $c->req->param( 'story_title' );
    my $story_description  = $c->req->param( 'story_description' );

    my $extractor_method = $c->req->param( 'extractor_method' );

    if ( defined( $extractor_method ) )
    {
        die unless ( $extractor_method eq 'HeuristicExtractor' ) or ( $extractor_method eq 'CrfExtractor' );
    }

    die unless defined( $preprocessed_lines );

    my $extractor = MediaWords::Util::ExtractorFactory::createExtractor( $extractor_method );

    my $ret = $extractor->extract_preprocessed_lines_for_story( $preprocessed_lines, $story_title, $story_description );
    $self->status_ok( $c, entity => $ret );
}

=head1 AUTHOR

Pamela Mishkin

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
