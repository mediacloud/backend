package MediaWords::Test::DB::Create::User;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use File::Path;
use Readonly;

use MediaWords::DB;
use MediaWords::DBI::Auth;

# Create a user for temporary databases
sub create_test_user($$)
{
    my ( $db, $label ) = @_;

    my $email = $label . '@em.ail';

    eval {
        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email           => $email,
            full_name       => $label,
            notes           => '',
            role_ids        => [ 1 ],
            active          => 1,
            password        => 'testtest',
            password_repeat => 'testtest',
            activation_url  => '',           # user is active, no need for activation URL
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    if ( $@ )
    {
        LOGCONFESS "Adding new user failed: $@";
    }

    my $user_info = MediaWords::DBI::Auth::Info::user_info( $db, $email );
    my $api_key = $user_info->global_api_key();

    return $api_key;
}

1;
