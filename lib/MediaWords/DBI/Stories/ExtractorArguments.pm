package MediaWords::DBI::Stories::ExtractorArguments;

#
# Arguments to process_extracted_story() that define how story is to be
# extracted
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;

sub new($;$)
{
    my ( $class, $args ) = @_;

    my $self = {};
    bless $self, $class;

    if ( $args )
    {
        unless ( ref $args eq ref {} )
        {
            LOGCONFESS "'args' is not a hashref.";
        }
    }

    $self->{ _no_dedup_sentences }    = $args ? $args->{ no_dedup_sentences }    : 0;
    $self->{ _no_delete }             = $args ? $args->{ no_delete }             : 0;
    $self->{ _skip_bitly_processing } = $args ? $args->{ skip_bitly_processing } : 0;
    $self->{ _use_cache }             = $args ? $args->{ use_cache }             : undef;

    return $self;
}

sub no_dedup_sentences($)
{
    my $self = shift;
    return $self->{ _no_dedup_sentences };
}

sub no_delete($)
{
    my $self = shift;
    return $self->{ _no_delete };
}

sub skip_bitly_processing($)
{
    my $self = shift;
    return $self->{ _skip_bitly_processing };
}

sub use_cache($)
{
    my $self = shift;
    return $self->{ _use_cache };
}

1;
