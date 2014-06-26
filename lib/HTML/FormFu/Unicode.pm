package HTML::FormFu::Unicode;

use strict;
use warnings;

use Carp;

use Data::Page;
use Encode;

use base qw(HTML::FormFu);

sub render
{
    my $self = shift @_;

    return encode( "UTF-8", $self->SUPER::render( @_ ) );
}

1;
