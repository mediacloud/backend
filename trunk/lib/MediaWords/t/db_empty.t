use strict;
use warnings;
use Dir::Self;
use Data::Dumper;

use Test::NoWarnings;
use Test::More tests => 7 + 1;

BEGIN
{
    use_ok( 'MediaWords::Util::Config' );
    use_ok( 'MediaWords::DB' );
    use_ok( 'DBIx::Simple::MediaWords' );
}

require_ok( 'MediaWords::Util::Config' );
require_ok( 'MediaWords::DB' );
require_ok( 'DBIx::Simple::MediaWords' );

eval { MediaWords::Util::Config::set_config_file( __DIR__ . '/db_empty.yml' ); };

isnt( $@, '', 'configurations need to specify >0 database connections' );
