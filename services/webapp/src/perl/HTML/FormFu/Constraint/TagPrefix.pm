package HTML::FormFu::Constraint::TagPrefix;

use strict;
use warnings;

use base 'HTML::FormFu::Constraint';

sub constrain_value
{
    my ( $self, $value ) = @_;

    my @tags = split( ' ', $value );

    for my $tag ( @tags )
    {
        if ( !( $tag =~ /\:/ ) )
        {
            return 0;
        }
    }

    return 1;
}

1;

__END__

=head1 NAME

HTML::FormFu::Constraint::TagPrefix - tag prefix constraint

=head1 DESCRIPTION

Require that each of the space separated tags has a ':'.

=head2 SEE ALSO

Is a sub-class of, and inherits methods from L<HTML::FormFu::Constraint>

L<HTML::FormFu::FormFu>

=head1 AUTHOR

Hal Roberts <hroberts@cyber.law.harvard.edu>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.
