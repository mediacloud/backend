package MediaWords::DBI::Stories::ExtractorArguments;

#
# Arguments to process_extracted_story() that define how story is to be
# extracted
#

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

    $self->{ no_dedup_sentences } = $args ? $args->{ no_dedup_sentences } : 0;
    $self->{ no_vector }          = $args ? $args->{ no_vector }          : 0;
    $self->{ no_delete }          = $args ? $args->{ no_delete }          : 0;

    return $self;
}

1;
