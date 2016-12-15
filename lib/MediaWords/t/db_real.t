use strict;
use warnings;

use Test::NoWarnings;
use Test::More tests => 2;

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

MediaWords::Util::Config::set_config_file( __DIR__ . "/../../../mediawords.yml" );

is( $@, '', 'Error setting the default config file' );
