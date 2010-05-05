package MediaWords::View::TT;

use strict;
use base 'Catalyst::View::TT';
use HTML::Strip;

sub new
{
    my $class = shift;
    my $self  = $class->NEXT::new(@_);
    $self->{template}->context->define_filter(
        round => sub {
            my $nr = shift;
            $nr = int($nr);
        }
    );

    $self->{template}->context->define_filter(
        html_strip => sub {
            my $nr = shift;
            my $hs = HTML::Strip->new();

            $nr = $hs->parse($nr);
        }
    );

    return $self;
}

=head1 NAME

MediaWords::View::TT - Catalyst TT View

=head1 SYNOPSIS

See L<MediaWords>

=head1 DESCRIPTION

Catalyst TT View.

=head1 AUTHOR

Hal Roberts

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
