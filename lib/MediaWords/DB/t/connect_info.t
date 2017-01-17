use strict;
use warnings;

use Test::NoWarnings;
use Test::More tests => 9;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MediaWords::DB;

use Dir::Self;

MediaWords::Util::Config::set_config_file( __DIR__ . '/connect_info.yml' );

{
    my ( $host, $port, $username, $password, $database ) = MediaWords::DB::connect_info();
    is( $host,     'localhost' );
    is( $username, 'mediaclouduser' );
    is( $password, 'secretpassword' );
    is( $database, 'mediacloud' );
}

{
    my ( $host, $port, $username, $password, $database ) = MediaWords::DB::connect_info( 'test' );
    is( $host,     'localhost' );
    is( $username, 'mediacloudtestuser' );
    is( $password, 'secretpassword' );
    is( $database, 'mediacloudtest' );
}
