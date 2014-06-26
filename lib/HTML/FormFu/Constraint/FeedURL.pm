package HTML::FormFu::Constraint::FeedURL;

use strict;
use warnings;

use base 'HTML::FormFu::Constraint';

use XML::FeedPP;

sub constrain_value
{
    my ( $self, $value ) = @_;

    eval { XML::FeedPP->new( $value ) };
    if ( $@ )
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

HTML::FormFu::Constraint::FeedURL - Feed URL constraint

=head1 DESCRIPTION

Checks that we can download the url and parse it as a feed with XML::FeedPP;

=head2 SEE ALSO

Is a sub-class of, and inherits methods from L<HTML::FormFu::Constraint>

L<HTML::FormFu::FormFu>

=head1 AUTHOR

Hal Roberts <hroberts@cyber.law.harvard.edu>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.
