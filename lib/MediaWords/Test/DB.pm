package MediaWords::Test::DB;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DB::Schema;
use MediaWords::Test::DB::Create;
use MediaWords::Test::DB::Environment;

# run the given function on a temporary, clean database
sub test_on_test_database
{
    my ( $sub ) = @_;

    MediaWords::DB::Schema::recreate_db( 'test' );

    my $db = MediaWords::DB::connect_to_db( 'test' );

    MediaWords::Test::DB::Environment::force_using_test_database();

    eval { $sub->( $db ); };

    if ( $@ )
    {
        die( $@ );
    }

    if ( $db )
    {
        $db->disconnect();
    }
}

1;
