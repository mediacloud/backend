use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../../../lib";
    use lib "$FindBin::Bin/../../lib";
    use lib "$FindBin::Bin/../../";
}

use Data::Dumper;
use MediaWords::Pg::Schema;

use Test::More tests => 12;

BEGIN
{
    use_ok( 'MediaWords::Util::Config' );
    use_ok( 'DBIx::Simple::MediaWords' );
    use_ok( 'MediaWords::DB' );
}

require_ok( 'MediaWords::Util::Config' );
require_ok( 'DBIx::Simple::MediaWords' );
require_ok( 'MediaWords::DB' );

my $dbs = MediaWords::DB::connect_to_db( 'test' );

isa_ok( $dbs, "DBIx::Simple::MediaWords" );

# clear the DB
MediaWords::Pg::Schema::_reset_schema( $dbs );

my $script_dir = MediaWords::Util::Config->get_config()->{ mediawords }->{ script_dir };
MediaWords::Pg::Schema::add_functions( $dbs );
my $load_sql_file_result = MediaWords::Pg::Schema::load_sql_file( 'test', "$script_dir/mediawords.sql" );

ok( $load_sql_file_result == 0, "load sql file result" );

# transaction success
$dbs->transaction(
    sub {
        $dbs->query( 'INSERT INTO media (url, name, moderated, feeds_added) VALUES(?, ?, ?, ?)',
            'http://www.example.com/', 'Example.com', 0, 0 );
        return 1;
    }
);

is( $dbs->query( 'SELECT COUNT(*) FROM media' )->list, '1', 'simple transaction' );

# transaction failure
eval {
    $dbs->transaction(
        sub {
            $dbs->query( 'INSERT INTO media (url, name, moderated, feeds_added) VALUES(?, ?, ?, ?)',
                'http://www.example.net/', 'Example.net', 0, 0 );
            die "I did too much work in the transaction!";
        }
    );
};

like( $@, qr/^I did too much work in the transaction!/, 'die propagation' );
is( $dbs->query( 'SELECT COUNT(*) FROM media' )->list, '1', 'exceptions roll-back transactions' );

# transaction abortion
$dbs->transaction(
    sub {
        $dbs->query( 'INSERT INTO media (url, name, moderated, feeds_added) VALUES(?, ?, ?, ?)',
            'http://www.example.org/', 'Example.org', 0, 0 );
        return 0;
    }
);

is( $dbs->query( 'SELECT COUNT(*) FROM media' )->list, '1', 'voluntary abortion' );

$dbs->disconnect();
