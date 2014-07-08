package HTML::FormFu::OutputProcessor::RemoveEndForm;

use strict;
use warnings;

use base 'HTML::FormFu::OutputProcessor';

sub process
{
    my ( $self, $input ) = @_;

    $input =~ s~</form>~~;

    return $input;
}

1;

__END__

=head1 NAME

HTML::FormFu::OutputProcessor::RemoveEndForm - remove end form tag

=head1 SYNOPSIS

Remove the end form tag.  Helpful to add more inputs to a form manually.

=head1 SEE ALSO

Is a sub-class of, and inherits methods from L<HTML::FormFu::OutputProcessor>

L<HTML::FormFu::FormFu>

=head1 AUTHOR

Hal Roberts <hroberts@cyber.law.harvard.edu>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.
