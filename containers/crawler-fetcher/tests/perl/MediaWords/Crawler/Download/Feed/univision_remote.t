#
# Test Univision feed implementation with remote source (if configured)
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::Test::Univision;
use MediaWords::DB;
use MediaWords::Util::Config::Crawler;

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    my $db = MediaWords::DB::connect_to_db();

    my $crawler_config = MediaWords::Util::Config::Crawler->new();
    
    my $remote_univision_url = $ENV{ 'MC_UNIVISION_TEST_URL' };
    my $remote_univision_client_id     = $crawler_config->univision_client_id();
    my $remote_univision_client_secret = $crawler_config->univision_client_secret();

    if ( $remote_univision_url and $remote_univision_client_id and $remote_univision_client_secret )
    {
        MediaWords::Test::Univision::test_univision(
            $db,                                #
            $remote_univision_url,              #
            $remote_univision_client_id,        #
            $remote_univision_client_secret,    #
        );
    } else {
        INFO "Skipping remote Univision test because it's not configured.";
    }

    done_testing();
}

main();
