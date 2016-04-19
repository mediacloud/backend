package MediaWords::View::TT;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use base 'Catalyst::View::TT';
use MediaWords::Util::HTML;
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

            #$Data::Dumper::Purity = 1;
            #$Data::Dumper::Useperl = 1;
            my $nr = shift;

            #say STDERR "Stripping: '$nr'"  if (length($nr) > 0 );
            ##say STDERR Dumper($nr)  if (length($nr) > 0 );
            $nr = html_strip( $nr );
            ##say STDERR Dumper($nr)  if (length($nr) > 0 );
            #say STDERR "Striped '$nr'"  if (length($nr) > 0 );
            #$nr;
        }
    );

    $self->{ template }->context->define_filter(
        url_encode => sub {

            #$Data::Dumper::Purity = 1;
            #$Data::Dumper::Useperl = 1;
            my $nr = shift;

            # say STDERR "encoding: '$nr'" if ( length( $nr ) > 0 );

            $nr =~ s/&/&amp;/g;

            # say STDERR "returning: '$nr'" if ( length( $nr ) > 0 );

            return $nr;
            ##say STDERR Dumper($nr)  if (length($nr) > 0 );
            #$nr = html_strip( $nr );
            ##say STDERR Dumper($nr)  if (length($nr) > 0 );
            #say STDERR "Striped '$nr'"  if (length($nr) > 0 );
            #$nr;
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
            my $ga_domain = $config->{ google_analytics } ? $config->{ google_analytics }->{ domainname } : '';

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
