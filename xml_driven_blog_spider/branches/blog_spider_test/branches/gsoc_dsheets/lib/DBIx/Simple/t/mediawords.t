use strict;
use warnings;

use Data::Dumper;

use Test::More tests => 10;

BEGIN {
    use_ok('MediaWords::Util::Config');
    use_ok('DBIx::Simple::MediaWords');
    use_ok('MediaWords::DB');
}

require_ok('MediaWords::Util::Config');
require_ok('DBIx::Simple::MediaWords');
require_ok('MediaWords::DB');

my $dbs =
    DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info('test'));

# clear the DB
$dbs->reset_schema();
$dbs->query("DROP SCHEMA IF EXISTS stories_tags_map_media_sub_tables CASCADE");

my $script_dir =
    MediaWords::Util::Config->get_config()->{mediawords}->{script_dir};
$dbs->load_sql_file("$script_dir/mediawords.sql");

# transaction success
$dbs->transaction(
    sub {
	$dbs->query('INSERT INTO media (url, name) VALUES(?, ?)',
		    'http://www.example.com/', 'Example.com');
	return 1;
    }
    );

is($dbs->query('SELECT COUNT(*) FROM media')->list, '1', 'simple transaction');

# transaction failure
eval {
    $dbs->transaction(
	sub {
	    $dbs->query('INSERT INTO media (url, name) VALUES(?, ?)',
			'http://www.example.net/', 'Example.net');
	    die "I did too much work in the transaction!";
	}
	);
};

like($@, qr/^I did too much work in the transaction!/,
     'die propagation');
is($dbs->query('SELECT COUNT(*) FROM media')->list, '1',
   'exceptions roll-back transactions');

# transaction abortion
$dbs->transaction(
    sub {
	$dbs->query('INSERT INTO media (url, name) VALUES(?, ?)',
		    'http://www.example.org/', 'Example.org');
	return 0;
    }
    );

is($dbs->query('SELECT COUNT(*) FROM media')->list, '1',
   'voluntary abortion');

$dbs->disconnect();
