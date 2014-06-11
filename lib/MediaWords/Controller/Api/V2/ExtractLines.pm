package MediaWords::Controller::Api::V2::ExtractLines;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::StorySubsets;
use strict;
use warnings;
use base 'Catalyst::Controller::REST';
use JSON;
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
        storyLines => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },    #
      }    #
);         #

use constant ROWS_PER_PAGE => 20;

use MediaWords::Tagger;

sub storyLines : Local : ActionClass('REST')    # action roles are to be set for each derivative sub-actions
{
}

sub storyLines_GET : Local
{
    my ( $self, $c ) = @_;

    my $body_html = $c->req->param( 'body_html' );
    $body_html //= ROWS_PER_PAGE;

    # say STDERR "rows $rows";

    my $lines = [ split( /[\n\r]+/, $body_html ) ];

    $lines = MediaWords::Crawler::Extractor::preprocess( $lines );

    $self->status_ok( $c, entity => $lines );
}

=head1 AUTHOR

Pamela Mishkin

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
