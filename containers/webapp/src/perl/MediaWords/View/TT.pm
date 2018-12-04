package MediaWords::View::TT;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use base 'Catalyst::View::TT';
use MediaWords::Util::ParseHTML;
use Data::Dumper;
use Text::Trim;
use MediaWords::Util::Config;

sub new
{
    my $class = shift;
    my $self  = $class->next::method( @_ );
    $self->{ template }->context->define_filter(
        round => sub {
            my $nr = shift;
            $nr = int( $nr );
        }
    );

    $self->{ template }->context->define_filter(
        html_strip => sub {
            my $nr = shift;
            $nr = MediaWords::Util::ParseHTML::html_strip( $nr );
        }
    );

    $self->{ template }->context->define_filter(
        url_encode => sub {
            my $nr = shift;
            $nr =~ s/&/&amp;/g;
            return $nr;
        }
    );

    $self->{ template }->context->define_filter(
        ga_account_code => sub {
            my $nr = shift;

            my $config = MediaWords::Util::Config::get_config;
            my $ga_code = $config->{ google_analytics } ? $config->{ google_analytics }->{ account } : '';

            $nr = $ga_code;

            return $nr;
        }
    );

    $self->{ template }->context->define_filter(
        ga_domainname => sub {
            my $nr = shift;

            my $config = MediaWords::Util::Config::get_config;
            my $ga_domain = $config->{ google_analytics } ? $config->{ google_analytics }->{ domainname } : 'auto';

            $nr = $ga_domain;

            return $nr;
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
