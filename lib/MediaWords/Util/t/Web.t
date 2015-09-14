use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::Deep;
use Test::More tests => 4;

use Readonly;
use Data::Dumper;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::Web' );
}

sub test_is_http_url()
{
    like(
        MediaWords::Util::Web::get_original_url_from_momento_archive_url(
            'https://web.archive.org/web/20150204024130/http://www.john-daly.com/hockey/hockey.htm'
        ),
        qr|^http://(www\.)?john\-daly\.com/hockey/hockey\.htm$|,
        'archive.org test '
    );

    like(
        MediaWords::Util::Web::get_original_url_from_momento_archive_url( 'https://archive.is/1Zcql' ),
        qr|^https?://www\.whitehouse\.gov/my2k/?$|,
        'archive.is test'
    );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_is_http_url();

}

main();
