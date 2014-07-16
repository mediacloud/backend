use strict;
use warnings;

#use Test::More;
use Test::More tests => 4;

BEGIN
{
    use MediaWords::Controller::Login;
    use MediaWords::Util::Config;
    MediaWords::Util::Config->get_config->{ mediawords }->{ allow_unauthenticated_api_requests } = 'yes';
}

$ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;
use_ok 'Catalyst::Test', 'MediaWords';
MediaWords::Util::Config->get_config->{ mediawords }->{ allow_unauthenticated_api_requests } = 'yes';

is( MediaWords::Util::Config->get_config->{ mediawords }->{ allow_unauthenticated_api_requests }, 'yes' );

ok( request( '/api/v2/media/list' )->is_success, 'Request should succeed' );
ok( request( '/api/v2/media/list' )->is_success, 'Request should succeed' );

done_testing();
