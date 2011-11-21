package MediaWords::Tagger;
use MediaWords::CommonLibs;


# analyze text and assign tags using various methods implemented in the MediaWords::Tagger::* modules

use strict;

BEGIN
{
    use constant MODULES => qw(NYTTopics Yahoo Calais);

    for my $module ( MODULES )
    {
        eval( "use MediaWords::Tagger::${module};" );
        if ( $@ )
        {
            die( "error loading $module: $@" );
        }
    }
}

sub get_all_tags
{
    my ( $text ) = @_;

    return get_tags_for_modules( $text, [ MODULES ] );
}

sub get_tags_for_modules
{
    my ( $text, $module_list ) = @_;

    my $all_tags = {};
    for my $module ( @{ $module_list } )
    {
        $all_tags->{ $module } = eval( "MediaWords::Tagger::${module}::get_tags( \$text )" );
        if ( $@ )
        {
            die( "error with module $module: $@" );
        }
    }

    return $all_tags;

}

1;
