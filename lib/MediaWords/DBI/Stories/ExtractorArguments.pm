package MediaWords::DBI::Stories::ExtractorArguments;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

{
    # Proxy to Python's implementation
    package MediaWords::DBI::Stories::ExtractorArguments::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    import_python_module( __PACKAGE__, 'mediawords.dbi.stories.extractor_arguments' );

    1;
}

sub new($;$)
{
    my ( $class, $args ) = @_;

    my $self = {};
    bless $self, $class;

    unless ( $args )
    {
        $args = {};
    }

    $self->{ _python_object } = MediaWords::DBI::Stories::ExtractorArguments::PythonProxy::ExtractorArguments->new(
        int( $args->{ no_dedup_sentences }       // 0 ),
        int( $args->{ no_delete }                // 0 ),
        int( $args->{ no_tag_extractor_version } // 0 ),
        int( $args->{ use_cache }                // 0 ),
        int( $args->{ use_existing }             // 0 ),
    );

    return $self;
}

sub no_dedup_sentences($)
{
    my $self = shift;
    return $self->{ _python_object }->no_dedup_sentences();
}

sub no_delete($)
{
    my $self = shift;
    return $self->{ _python_object }->no_delete();
}

sub no_tag_extractor_version($)
{
    my $self = shift;
    return $self->{ _python_object }->no_tag_extractor_version();
}

sub use_cache($)
{
    my $self = shift;
    return $self->{ _python_object }->use_cache();
}

sub use_existing($)
{
    my $self = shift;
    return $self->{ _python_object }->use_existing();
}

1;
