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
