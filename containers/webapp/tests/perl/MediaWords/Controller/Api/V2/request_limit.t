use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Catalyst::Test 'MediaWords';

use Readonly;
use Test::More tests => 25;
use Test::Deep;

use Readonly;
use URI;
use URI::QueryParam;
use HTTP::Status qw(:constants);

use MediaWords::Test::API;

use MediaWords::DBI::Auth;
use MediaWords::Util::Mail;
use MediaWords::Util::ParseJSON;

sub test_request_limit($)
{
    my ( $db ) = @_;

    MediaWords::Test::API::setup_test_api_key( $db );

    my $email          = 'test@auth.request_limit';
    my $password       = 'authrequestlimit';
    my $activation_url = 'https://activate.com/activate';

    Readonly my $weekly_requests_limit => 3;

    my $limited_user_api_key;

    # Register user
    {
        my $r = MediaWords::Test::API::test_post(
            '/api/v2/auth/register',
            {
                email                   => $email,
                password                => $password,
                full_name               => 'Full Name',
                notes                   => '',
                subscribe_to_newsletter => 1,
                activation_url          => 'https://activate.com/',
            }
        );
        is( $r->{ 'success' }, 1 );

        # Send password reset link
        my $final_activation_url =
          MediaWords::DBI::Auth::Register::_generate_user_activation_token( $db, $email, $activation_url );
        ok( $final_activation_url );
        like( $final_activation_url, qr/\Qactivation_token\E/ );

        my $final_activation_uri = URI->new( $final_activation_url );
        ok( $final_activation_uri->query_param( 'email' ) . '' );
        my $activation_token = $final_activation_uri->query_param( 'activation_token' );
        ok( $activation_token );
        ok( length( $activation_token ) > 1 );

        # Activate user
        MediaWords::DBI::Auth::Register::activate_user_via_token( $db, $email, $activation_token );

        # Confirm that we can log in
        my $user;
        eval { $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password ); };
        ok( !$@ );
        is( $user->email, $email );
        ok( $user->global_api_key() );

        $limited_user_api_key = $user->global_api_key();

        # Set the request limit
        $db->query(
            <<SQL,
            UPDATE auth_user_limits
            SET weekly_requests_limit = ?
            WHERE auth_users_id = ?
SQL
            $weekly_requests_limit, $user->user_id()
        );
    }

    # Use up the requests
    my $requests_left = $weekly_requests_limit;
    for ( ; $requests_left > 0 ; --$requests_left )
    {

        # Catalyst::Test::request()
        my $response = request( '/api/v2/auth/profile?key=' . $limited_user_api_key );
        ok( $response->is_success );

        my $profile = MediaWords::Util::ParseJSON::decode_json( $response->decoded_content );
        ok( $profile );
        is( $profile->{ email }, $email );
    }

    # Should have ran out of requests at this point

    # Catalyst::Test::request()
    my $response = request( '/api/v2/auth/profile?key=' . $limited_user_api_key );
    ok( !$response->is_success );
    is( $response->code(), HTTP_TOO_MANY_REQUESTS );

    my $profile = MediaWords::Util::ParseJSON::decode_json( $response->decoded_content );
    ok( $profile->{ error } );
    like( $profile->{ error }, qr/exceeded weekly requests/i );
}

sub main
{
    # Don't actually send any emails
    MediaWords::Util::Mail::enable_test_mode();

    my $db = MediaWords::DB::connect_to_db();

    test_request_limit( $db );
}

main();
