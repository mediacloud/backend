package MediaWords::DBI::Stories::ExtractorArguments;

#
# Arguments to process_extracted_story() that define how story is to be
# extracted
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub new($;$)
{
    my ( $class, $args ) = @_;

    my $self = {};
    bless $self, $class;

    if ( $args )
    {
        unless ( ref $args eq ref {} )
        {
            die "'args' is not a hashref.";
        }
    }

    $self->{ _no_dedup_sentences } = $args ? $args->{ no_dedup_sentences } : 0;
    $self->{ _no_vector }          = $args ? $args->{ no_vector }          : 0;
    $self->{ _no_delete }          = $args ? $args->{ no_delete }          : 0;

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

1;
