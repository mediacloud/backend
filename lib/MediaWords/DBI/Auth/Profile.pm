package MediaWords::DBI::Auth::Profile;

#
# User profile helpers
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

use MediaWords::DBI::Auth::ChangePassword;
use MediaWords::DBI::Auth::User::ModifyUser;
use MediaWords::Util::Mail;

# Fetch and return a list of users and their roles; returns an arrayref
sub all_users($)
{
    my ( $db ) = @_;

    # Start a transaction so that the list of users doesn't change while we run
    # separate queries with MediaWords::DBI::Auth::Info::user_info()
    $db->begin;

    my $user_emails = $db->query(
        <<"SQL"
            SELECT email
            FROM auth_users
            ORDER BY auth_users_id
SQL
    )->flat;

    my $users = [];

    foreach my $email ( @{ $user_emails } )
    {
        my $user = MediaWords::DBI::Auth::Info::user_info( $db, $email );
        push( @{ $users }, $user );
    }

    $db->commit;

    return $users;
}

# Update an existing user; die() on error
# Undefined user fields won't be set.
sub update_user($$)
{
    my ( $db, $existing_user ) = @_;

    unless ( $existing_user )
    {
        die "Existing user is undefined.";
    }
    unless ( ref( $existing_user ) eq 'MediaWords::DBI::Auth::User::ModifyUser' )
    {
        die "Existing user is not MediaWords::DBI::Auth::User::ModifyUser.";
    }

    TRACE "Modifying user: " . MediaWords::Util::Log::dump_terse( $existing_user );

    # Check if user exists
    my $userinfo;
    eval { $userinfo = MediaWords::DBI::Auth::Info::user_info( $db, $existing_user->email() ); };
    if ( $@ or ( !$userinfo ) )
    {
        die 'User with email address "' . $existing_user->email() . '" does not exist.';
    }

    # Begin transaction
    $db->begin_work;

    if ( defined( $existing_user->full_name() ) )
    {
        $db->query(
            <<SQL,
            UPDATE auth_users
            SET full_name = ?
            WHERE email = ?
SQL
            $existing_user->full_name(), $existing_user->email()
        );
    }

    if ( defined( $existing_user->notes() ) )
    {
        $db->query(
            <<SQL,
            UPDATE auth_users
            SET notes = ?
            WHERE email = ?
SQL
            $existing_user->notes(), $existing_user->email()
        );
    }

    if ( defined( $existing_user->active() ) )
    {
        $db->query(
            <<SQL,
            UPDATE auth_users
            SET active = ?
            WHERE email = ?
SQL
            normalize_boolean_for_db( $existing_user->active() ), $existing_user->email()
        );
    }

    if ( defined $existing_user->password() )
    {
        eval {
            Readonly my $do_not_inform_via_email => 1;
            MediaWords::DBI::Auth::ChangePassword::change_password(
                $db,
                $existing_user->email(),
                $existing_user->password(),
                $existing_user->password_repeat(),
                $do_not_inform_via_email
            );
        };
        if ( $@ )
        {
            my $error_message = "Unable to change password: $@";

            $db->rollback;
            die $error_message;
        }
    }

    if ( defined( $existing_user->weekly_requests_limit() ) )
    {
        $db->query(
            <<SQL,
            UPDATE auth_user_limits
            SET weekly_requests_limit = ?
            WHERE auth_users_id = ?
SQL
            $existing_user->weekly_requests_limit(), $userinfo->id()
        );
    }

    if ( defined( $existing_user->weekly_requested_items_limit() ) )
    {
        $db->query(
            <<SQL,
            UPDATE auth_user_limits
            SET weekly_requested_items_limit = ?
            WHERE auth_users_id = ?
SQL
            $existing_user->weekly_requested_items_limit(), $userinfo->id()
        );
    }

    if ( defined( $existing_user->role_ids() ) )
    {

        $db->query(
            <<SQL,
            DELETE FROM auth_users_roles_map
            WHERE auth_users_id = ?
SQL
            $userinfo->id()
        );
        for my $auth_roles_id ( @{ $existing_user->role_ids() } )
        {
            $db->query(
                <<SQL,
                INSERT INTO auth_users_roles_map (auth_users_id, auth_roles_id) VALUES (?, ?)
SQL
                $userinfo->id(), $auth_roles_id
            );
        }
    }

    # End transaction
    $db->commit;
}

# Delete user; die()s on error
sub delete_user($$)
{
    my ( $db, $email ) = @_;

    # Check if user exists
    my $userinfo;
    eval { $userinfo = MediaWords::DBI::Auth::Info::user_info( $db, $email ); };
    if ( $@ or ( !$userinfo ) )
    {
        die "User with email address '$email' does not exist.";
    }

    # Delete the user (PostgreSQL's relation will take care of 'auth_users_roles_map')
    $db->query(
        <<SQL,
        DELETE FROM auth_users
        WHERE email = ?
SQL
        $email
    );
}

# Regenerate API key -- creates new non-IP limited API key, removes all
# IP-limited API keys; die()s on error
sub regenerate_api_key($$)
{
    my ( $db, $email ) = @_;

    unless ( $email )
    {
        die 'Email address is empty.';
    }

    # Check if user exists
    my $userinfo;
    eval { $userinfo = MediaWords::DBI::Auth::Info::user_info( $db, $email ); };
    if ( $@ or ( !$userinfo ) )
    {
        die "User with email address '$email' does not exist.";
    }

    $db->begin;

    # Purge all IP-limited API keys
    $db->query(
        <<SQL,
        DELETE FROM auth_user_api_keys
        WHERE ip_address IS NOT NULL
          AND auth_users_id = (
            SELECT auth_users_id
            FROM auth_users
            WHERE email = ?
          )
SQL
        $email
    );

    # Regenerate non-IP limited API key
    $db->query(
        <<SQL,
        UPDATE auth_user_api_keys

        -- DEFAULT points to a generation function
        SET api_key = DEFAULT

        WHERE ip_address IS NULL
          AND auth_users_id = (
            SELECT auth_users_id
            FROM auth_users
            WHERE email = ?
          )        
SQL
        $email
    );

    eval {

        my $message = MediaWords::Util::Mail::Message::Templates::AuthAPIKeyResetMessage->new(
            {
                to        => $email,
                full_name => $userinfo->full_name(),
            }
        );
        unless ( MediaWords::Util::Mail::send_email( $message ) )
        {
            die "Unable to send email message.";
        }

    };
    if ( $@ )
    {
        $db->rollback;
        WARN "Unable to send email about reset API key: $@";
        die "Unable to send email about reset API key.";
    }

    $db->commit;
}

1;
