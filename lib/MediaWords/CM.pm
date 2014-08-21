package MediaWords::CM;

# General controversy mapper utilities

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use Getopt::Long;
use Data::Dumper;
use MediaWords::DBI::Queries;

# get a list controversies that match the controversy option, which can either be an id
# or a pattern that matches controversy names. Die if no controversies are found.
sub require_controversies_by_opt
{
    my ( $db, $controversy_opt ) = @_;

    if ( !defined( $controversy_opt ) )
    {
        Getopt::Long::GetOptions( "controversy=s" => \$controversy_opt ) || return;
    }

    die( "Usage: $0 --controversy < id or pattern >" ) unless ( $controversy_opt );

    my $controversies;
    if ( $controversy_opt =~ /^\d+$/ )
    {
        $controversies = $db->query( "select * from controversies where controversies_id = ?", $controversy_opt )->hashes;
        die( "No controversies found by id '$controversy_opt'" ) unless ( @{ $controversies } );
    }
    else
    {
        $controversies = $db->query( "select * from controversies where name ~* ?", '^' . $controversy_opt . '$' )->hashes;
        die( "No controversies found by pattern '$controversy_opt'" ) unless ( @{ $controversies } );
    }

    return $controversies;
}

1;
