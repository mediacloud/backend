package MediaWords::Util::Stemmer;
use MediaWords::CommonLibs;

use Moose;
use strict;
use warnings;

use Perl6::Say;
use Data::Dumper;
use MediaWords::Pg;

use Lingua::Stem;
use Lingua::Stem::Snowball;

has '_english_stemmer' => (
    is => 'rw',

    #			   default => sub {Lingua::Stem->new; } ,
    default => sub {
        Lingua::Stem::Snowball->new(
            lang     => 'en',
            encoding => 'UTF-8'
        );
    },
);

has '_russian_stemmer' => (
    is      => 'rw',
    default => sub {
        Lingua::Stem::Snowball->new(
            lang     => 'ru',
            encoding => 'UTF-8'
        );
    },
);

sub debug_output
{
    if ( $MediaWords::Pg::in_pl_perl )
    {
        pg_log( @_ );
    }
    else
    {
        say STDERR @_;
    }

    return;
}

sub stem
{
    my $self  = shift;
    my @words = @_;

    $@ = '';
    my $en_stemmer = Lingua::Stem::Snowball->new( lang => 'en', encoding => 'UTF-8' );
    die $@ if $@;

    $@ = '';
    my $ru_stemmer = Lingua::Stem::Snowball->new( lang => 'ru', encoding => 'UTF-8' );

    die $@ if $@;

    my @stems = $en_stemmer->stem( \@words );
    $ru_stemmer->stem_in_place( \@stems );

    return \@stems;
}

1;
