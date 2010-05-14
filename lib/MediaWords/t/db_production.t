use strict;
use warnings;
use Dir::Self;
use Data::Dumper;
use Test::More tests => 11;

BEGIN
{
    use_ok( 'MediaWords::Util::Config' );
    use_ok( 'MediaWords::DB' );
    use_ok( 'DBIx::Simple::MediaWords' );
}

require_ok( 'MediaWords::Util::Config' );
require_ok( 'MediaWords::DB' );
require_ok( 'DBIx::Simple::MediaWords' );

MediaWords::Util::Config::set_config_file( __DIR__ . '/db_production.yml' );

my ( $connect, $user, $password, $options ) = MediaWords::DB::connect_info();

is( $connect, 'dbi:Pg:dbname=mediacloud;host=localhost', 'connection string creation' );

is( $user, 'mediaclouduser', 'username capture' );

is( $password, 'secretpassword', 'password capture' );

( $connect, $user, $password, $options ) = MediaWords::DB::connect_info( 'test' );

is( $connect, 'dbi:Pg:dbname=mediacloudtest;host=localhost', 'labeled connection string creation' );

is( $user, 'mediacloudtestuser', 'labeled username capture' );
