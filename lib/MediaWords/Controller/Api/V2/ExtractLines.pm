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
              # story_lines => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },    #
        story_lines_PUT              => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },    #
        extractor_training_lines_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
      }    #
);         #

use constant ROWS_PER_PAGE => 20;

use MediaWords::Tagger;

sub story_lines : Local : ActionClass('REST')
{
}

sub story_lines_GET : Local
{
}

sub story_lines_PUT : Local
{
    my ( $self, $c ) = @_;

    #say STDERR Dumper( $c->req->params );
    #say STDERR Dumper( $c->req->data );

    say STDERR "body_html";
    my $body_html = $c->req->data->{ body_html };

    say STDERR "body_html";
    say STDERR length( $body_html );

    my $lines = [ split( /[\n\r]+/, $body_html ) ];

    $lines = MediaWords::Crawler::Extractor::preprocess( $lines );

    $self->status_ok( $c, entity => $lines );
}

# sub story_lines_GET : Local
# {
#     my ( $self, $c ) = @_;

#     say STDERR "body_html";

#     my $body_html = $c->req->param( 'body_html' );

#     #$body_html //= ROWS_PER_PAGE;

#     say STDERR "body_html";
#     say STDERR length($body_html);

#     my $lines = [ split( /[\n\r]+/, $body_html ) ];

#     $lines = MediaWords::Crawler::Extractor::preprocess( $lines );

#     $self->status_ok( $c, entity => $lines );
# }

sub extract : Local : ActionClass('REST')    # action roles are to be set for each derivative sub-actions
{
}

sub extract_PUT : Local
{
    my ( $self, $c ) = @_;

    my $preprocessed_lines = $c->req->data->{ preprocessed_lines };
    my $story_title        = $c->req->data->{ 'story_title' };
    my $story_description  = $c->req->data->{ 'story_description' };

    my $extractor_method = $c->req->data->{ 'extractor_method' };

    if ( defined( $extractor_method ) )
    {
        die unless ( $extractor_method eq 'HeuristicExtractor' ) or ( $extractor_method eq 'CrfExtractor' );
    }

    die unless defined( $preprocessed_lines );

    my $extractor = MediaWords::Util::ExtractorFactory::createExtractor( $extractor_method );

    my $ret = $extractor->extract_preprocessed_lines_for_story( $preprocessed_lines, $story_title, $story_description );
    $self->status_ok( $c, entity => $ret );
}

sub extractor_training_lines : Local : ActionClass('REST')
{
}

sub extractor_training_lines_GET : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    my $query = "select * from extractor_training_lines where downloads_id = ? ";

    my $items = $c->dbis->query( $query, $downloads_id )->hashes();

    $self->status_ok( $c, entity => $items );
}

=head1 AUTHOR

Pamela Mishkin

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
