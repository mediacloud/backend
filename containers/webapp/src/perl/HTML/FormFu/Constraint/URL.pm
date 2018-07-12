package HTML::FormFu::Constraint::URL;

use strict;
use warnings;

use base 'HTML::FormFu::Constraint';

use Regexp::Common qw /URI/;

sub constrain_value
{
    my ( $self, $value ) = @_;

    if ( !( $value =~ /$RE{URI}/ ) )
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

HTML::FormFu::Constraint::URL - url constraint

=head1 DESCRIPTION

Checks that the value is a url according to Regexp::Common::URI;

=head2 SEE ALSO

Is a sub-class of, and inherits methods from L<HTML::FormFu::Constraint>

L<HTML::FormFu::FormFu>

=head1 AUTHOR

Hal Roberts <hroberts@cyber.law.harvard.edu>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.
