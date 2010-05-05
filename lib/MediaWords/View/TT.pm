package MediaWords::View::TT;

use strict;
use base 'Catalyst::View::TT';
use MediaWords::Util::HTML;
use MediaWords::Util::Translate;
use Data::Dumper;
use Text::Trim;

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
	    #$Data::Dumper::Purity = 1;
	    #$Data::Dumper::Useperl = 1;
            my $nr = shift;
	    #say STDERR "Stripping: '$nr'"  if (length($nr) > 0 );
	    ##say STDERR Dumper($nr)  if (length($nr) > 0 );
            $nr = html_strip($nr);
	    ##say STDERR Dumper($nr)  if (length($nr) > 0 );
	    #say STDERR "Striped '$nr'"  if (length($nr) > 0 );
	    #$nr;
        }
    );

    $self->{template}->context->define_filter(
        translate => sub {
            my $nr = shift;
            $nr =  MediaWords::Util::Translate::translate($nr);
            #$nr = html_strip($nr);
        }
    );

    $self->{template}->context->define_filter(
        translate_if_necessary => sub {
            my $nr = shift;

	    return $nr if !defined($nr) || !defined(trim($nr));

            my $tr =  MediaWords::Util::Translate::translate($nr);
	    if ($tr eq $nr)
	    {
	       return $nr;
	    }
	    else
	    {
	      $nr = html_strip("$nr ($tr)");
	      return $nr;
	    }
            #$nr = html_strip($nr);
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
