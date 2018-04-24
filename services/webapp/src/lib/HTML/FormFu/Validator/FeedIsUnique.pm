package HTML::FormFu::Validator::FeedIsUnique;

use strict;
use warnings;
use base 'HTML::FormFu::Validator';
use Data::Dumper;

sub validate_value
{
    my ( $self, $value, $params ) = @_;

    my $c = $self->form->stash->{ context };

    my $duplicate_feed =
      $c->dbis->query( "select count(feeds_id) as is_duplicate_feed from feeds where url = ?", trim( $value ) )->hashes;
    my $is_duplicate_feed = @{ $duplicate_feed }[ 0 ]->{ is_duplicate_feed } + 0;
    if ( $is_duplicate_feed > 0 )
    {
        return 0;
    }
    else
    {
        return 1;
    }
}

1;

__END__

=head1 NAME

HTML::FormFu::Validator::FeedIsUnique - Feed uniqueness validator

=head1 DESCRIPTION

Check if the feed with the same URL is already present in the database.

=head2 SEE ALSO

Is a sub-class of, and inherits methods from L<HTML::FormFu::Validator>

L<HTML::FormFu::FormFu>

=head1 AUTHOR

Linas Valiukas <lvaliukas@cyber.law.harvard.edu>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.
