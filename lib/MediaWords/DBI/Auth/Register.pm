package MediaWords::DBI::Auth::Register;

#
# New user registration helpers
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;
use URI::Escape;

use MediaWords::DBI::Auth::Login;
use MediaWords::DBI::Auth::Password;
use MediaWords::DBI::Auth::Profile;
use MediaWords::DBI::Auth::User::NewUser;
use MediaWords::Util::Mail;
use MediaWords::Util::Log;
use MediaWords::Util::Text;

sub _send_new_user_email($$)
{
    my ( $email, $password_reset_link ) = @_;

    my $email_subject = 'Welcome to Media Cloud';
    my $email_message = <<"EOF";
Welcome to Media Cloud.

The Media Cloud team is committed to providing open access to our code, tools, and
data so that other folks can build on the work we have done to better understand
how online media impacts our society.

A Media Cloud user has been created for you.  To activate the user, please
visit the below link to set your password:

$password_reset_link

You can use this user account to access user restricted Media Cloud tools like the
Media Meter dashboard and to make calls to the Media Cloud API.  For information
about our tools and API, visit:

https://mediacloud.org/tools

If you have any questions about the Media Cloud project, tools, or data, please ask them
on the mediacloud group here:

https://groups.io/g/mediacloud

We encourage you to join the above group just to share how you are using
Media Cloud with a community of folks working on interesting research about
media systems, even if you do not have any specific questions.

If you have questions about your account or other private questions email
info\@mediacloud.org.

EOF

    unless ( MediaWords::Util::Mail::send( $email, $email_subject, $email_message ) )
    {
        die 'The user was created, but I was unable to send you an activation email.';
    }
}

# Prepare for password reset by emailing the password reset token; die()s on error
sub _send_user_activation_token($$$)
{
    my ( $db, $email, $password_reset_link ) = @_;

    unless ( $email )
    {
        die 'Email address is empty.';
    }
    unless ( $password_reset_link )
    {
        die 'Password reset link is empty.';
    }

    # Check if the email address exists in the user table; if not, pretend that
    # we sent the password reset link with a "success" message.
    # That way the adversary would not be able to find out which email addresses
    # are active users.
    #
    # (Possible improvement: make the script work for the exact same amount of
    # time in both cases to avoid timing attacks)
    my $user_exists = $db->query(
        <<"SQL",
        SELECT auth_users_id,
               email
        FROM auth_users
        WHERE email = ?
        LIMIT 1
SQL
        $email
    )->hash;

    if ( !( ref( $user_exists ) eq ref( {} ) and $user_exists->{ auth_users_id } ) )
    {

        # User was not found, so set the email address to an empty string, but don't
        # return just now and continue with a rather slowish process of generating a
        # password reset token (in order to reduce the risk of timing attacks)
        $email = '';
    }

    # Generate the password reset token
    my $password_reset_token = MediaWords::Util::Text::random_string( 64 );
    unless ( length( $password_reset_token ) > 0 )
    {
        die 'Unable to generate a password reset token.';
    }

    # Hash + validate the password reset token
    my $password_reset_token_hash;
    eval { $password_reset_token_hash = MediaWords::DBI::Auth::Password::generate_secure_hash( $password_reset_token ); };
    if ( $@ or ( !$password_reset_token_hash ) )
    {
        die "Unable to hash a password reset token: $@";
    }

    # Set the password token hash in the database
    # (if the email address doesn't exist, this query will do nothing)
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET password_reset_token_hash = ?
        WHERE email = ? AND email != ''
SQL
        $password_reset_token_hash, $email
    );

    # If we didn't find an email address in the database, we return here imitating success
    # (again, due to timing attacks)
    unless ( length( $email ) > 0 )
    {
        return;
    }

    $password_reset_link =
      $password_reset_link . '?email=' . uri_escape( $email ) . '&token=' . uri_escape( $password_reset_token );
    INFO "Full password reset link: $password_reset_link";

    eval { _send_new_user_email( $email, $password_reset_link ); };
    if ( $@ )
    {
        my $error_message = "Unable to send email to user: $@";
        die $error_message;
    }
}

# Add new user; $role_ids is a arrayref to an array of role IDs; die()s on error
sub add_user($$)
{
    my ( $db, $new_user ) = @_;

    unless ( $new_user )
    {
        die "New user is undefined.";
    }
    unless ( ref( $new_user ) eq 'MediaWords::DBI::Auth::User::NewUser' )
    {
        die "New user is not MediaWords::DBI::Auth::User::NewUser.";
    }

    INFO "Creating user: " . MediaWords::Util::Log::dump_terse( $new_user );

    # Check if user already exists
    my ( $user_exists ) = $db->query(
        <<"SQL",
        SELECT 1
        FROM auth_users
        WHERE email = ?
SQL
        $new_user->email()
    )->flat;
    if ( $user_exists )
    {
        die "User with email '" . $new_user->email() . "' already exists.";
    }

    # Hash + validate the password
    my $password_hash;
    eval { $password_hash = MediaWords::DBI::Auth::Password::generate_secure_hash( $new_user->password() ); };
    if ( $@ or ( !$password_hash ) )
    {
        die 'Unable to hash a new password.';
    }

    # Begin transaction
    $db->begin_work;

    # Create the user
    $db->create(
        'auth_users',
        {
            email         => $new_user->email(),
            password_hash => $password_hash,
            full_name     => $new_user->full_name(),
            notes         => $new_user->notes(),
            active        => normalize_boolean_for_db( $new_user->active() )
        }
    );

    # Fetch the user's ID
    my $userinfo = undef;
    eval { $userinfo = MediaWords::DBI::Auth::Profile::user_info( $db, $new_user->email() ); };
    if ( $@ or ( !$userinfo ) )
    {
        $db->rollback;
        die "I've attempted to create the user but it doesn't exist: $@";
    }
    my $auth_users_id = $userinfo->{ auth_users_id };

    # Create roles
    for my $auth_roles_id ( @{ $new_user->role_ids() } )
    {
        $db->query(
            <<SQL,
            INSERT INTO auth_users_roles_map (auth_users_id, auth_roles_id)
            VALUES (?, ?)
SQL
            $auth_users_id, $auth_roles_id
        );
    }

    # Update limits (if they're defined)
    if ( defined $new_user->weekly_requests_limit() )
    {
        $db->query(
            <<SQL,
            UPDATE auth_user_limits
            SET weekly_requests_limit = ?
            WHERE auth_users_id = ?
SQL
            $new_user->weekly_requests_limit(), $auth_users_id
        );
    }

    if ( defined $new_user->weekly_requested_items_limit() )
    {
        $db->query(
            <<SQL,
            UPDATE auth_user_limits
            SET weekly_requested_items_limit = ?
            WHERE auth_users_id = ?
SQL
            $new_user->weekly_requested_items_limit(), $auth_users_id
        );
    }

    unless ( $new_user->active() )
    {
        _send_user_activation_token( $db, $new_user->email(), $new_user->activation_url() );
    }

    # End transaction
    $db->commit;
}

# Change password with a password token sent by email; die()s on error
sub activate_user_via_token($$$)
{
    my ( $db, $email, $password_reset_token ) = @_;

    unless ( $password_reset_token )
    {
        die 'Password reset token is empty.';
    }

    # Validate the token once more (was pre-validated in controller)
    unless ( MediaWords::DBI::Auth::Password::password_reset_token_is_valid( $db, $email, $password_reset_token ) )
    {
        die 'Password reset token is invalid.';
    }

    # Set the password hash
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET active = TRUE
        WHERE email = ?
SQL
        $email
    );

    # Unset the password reset token
    MediaWords::DBI::Auth::Login::post_successful_login( $db, $email );
}

1;
