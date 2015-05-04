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

use constant ROWS_PER_PAGE => 20;

BEGIN
{
    extends 'MediaWords::Controller::Api::V2::StoriesBase'    # private
}

sub has_extra_data
{
    return 0;
}

sub permissible_output_fields
{
    return [
        qw ( stories_id media_id media_name media_url processed_stories_id url guid publish_date collect_date story_tags )
    ];
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
