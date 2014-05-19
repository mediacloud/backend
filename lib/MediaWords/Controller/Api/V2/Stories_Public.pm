package MediaWords::Controller::Api::V2::Stories_Public;
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

use MediaWords::DBI::Stories;
use MediaWords::Solr;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

__PACKAGE__->config( action_roles => [ 'PublicApiKeyAuthenticated' ], );

use constant ROWS_PER_PAGE => 20;

use MediaWords::Tagger;

BEGIN { extends 'MediaWords::Controller::Api::V2::StoriesBase' }

__PACKAGE__->config( action_roles => [ 'NonPublicApiKeyAuthenticated' ], );

sub permissible_output_fields
{
    return [ qw ( stories_id url guid publish_date collect_date story_tags ) ];
}

sub has_extra_data
{
    return 0;
}

sub has_nested_data
{
    return 0;
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
