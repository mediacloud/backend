package MediaWords::Controller::Api::V2::Crawler;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

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
use MediaWords::DBI::Downloads;

=head1 NAME

MediaWords::Controller::Api::V2::Crawler - Catalyst Controller

=head1 DESCRIPTION


=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

# Default authentication action roles
__PACKAGE__->config(    #
    action => {         #
        add_feed_download_PUT => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] },    #
      }    #
);         #

use constant ROWS_PER_PAGE => 20;

sub add_feed_download : Local : ActionClass('REST')
{
}

sub add_feed_download_PUT : Local
{
    my ( $self, $c ) = @_;

    #say STDERR Dumper( $c->req->params );
    #say STDERR Dumper( $c->req->data );

    my $download        = $c->req->data->{ download };
    my $decoded_content = $c->req->data->{ raw_content };

    #say STDERR Dumper ( $download );

    $download->{ downloads_id } = undef;
    delete $download->{ downloads_id };

    $download = $c->dbis->create( 'downloads', $download );

    MediaWords::Crawler::FeedHandler::handle_feed_content( $c->dbis, $download, $decoded_content );

    $self->status_ok( $c, entity => $download );
}

1;
