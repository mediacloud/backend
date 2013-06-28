package HTML::FormFu::Validator::MediumUrlIsUnique;

use strict;
use warnings;
use base 'HTML::FormFu::Validator';

sub validate_value
{
    my ( $self, $value, $params ) = @_;

    my $c        = $self->form->stash->{ c };
    my $db       = $c->dbis;
    my $media_id = $c->req->args->[ 0 ];

    $value =~ s/^\s+|\s+$//g;

    my $existing_medium = $db->query( <<END, $media_id, $value )->hash;
select * from media where media_id <> ? and url = ?
END

    return 1 unless ( $existing_medium );

    die HTML::FormFu::Exception::Validator->new( { message => 'Medium with that url already exists' } );
}

1;
