use strict;
use warnings;

use Test::NoWarnings;
use Test::More tests => 6;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MediaWords::DB;
use DBIx::Simple::MediaWords;

use Dir::Self;
use Data::Dumper;

MediaWords::Util::Config::set_config_file( __DIR__ . '/db_production.yml' );

my ( $connect, $user, $password, $options ) = MediaWords::DB::connect_info();

is( $connect, 'dbi:Pg:dbname=mediacloud;host=localhost', 'connection string creation' );

is( $user, 'mediaclouduser', 'username capture' );

is( $password, 'secretpassword', 'password capture' );

( $connect, $user, $password, $options ) = MediaWords::DB::connect_info( 'test' );

is( $connect, 'dbi:Pg:dbname=mediacloudtest;host=localhost', 'labeled connection string creation' );

is( $user, 'mediacloudtestuser', 'labeled username capture' );
