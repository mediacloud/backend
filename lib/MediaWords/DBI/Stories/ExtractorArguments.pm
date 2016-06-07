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
    $self->{ _no_vector }             = $args ? $args->{ no_vector }             : 0;
    $self->{ _no_delete }             = $args ? $args->{ no_delete }             : 0;
    $self->{ _skip_bitly_processing } = $args ? $args->{ skip_bitly_processing } : 0;
    $self->{ _extractor_method }      = $args ? $args->{ extractor_method }      : undef;

    return $self;
}

sub no_dedup_sentences($)
{
    my $self = shift;
    return $self->{ _no_dedup_sentences };
}

sub no_vector($)
{
    my $self = shift;
    return $self->{ _no_vector };
}

sub no_delete($)
{
    my $self = shift;
    return $self->{ _no_delete };
}

sub skip_bitly_processing($)
{
    my $self = shift;
    return $self->{ skip_bitly_processing };
}

# Falls back to default extractor method in configuration
sub extractor_method($)
{
    my $self = shift;

    if ( $self->{ _extractor_method } )
    {
        return $self->{ _extractor_method };
    }
    else
    {
        my $config = MediaWords::Util::Config::get_config;
        return $config->{ mediawords }->{ extractor_method };
    }
}

1;
