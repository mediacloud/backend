package MediaWords::DBI::Auth::ResetPassword;

#
# User password resetting helpers (when password is not known)
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth::Login;
use MediaWords::DBI::Auth::Password;
use MediaWords::Util::Text;
use MediaWords::Util::Mail;

use URI::Escape;

# Generate password reset token
# Kept in a separate subroutine for easier testing.
# Returns undef if user was not found.
sub _generate_password_reset_token($$$)
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

    if ( $email )
    {
        return $password_reset_link .
          '?email=' . uri_escape( $email ) . '&password_reset_token=' . uri_escape( $password_reset_token );
    }
    else
    {
        return undef;
    }
}

# Prepare for password reset by emailing the password reset token; die()s on error
sub send_password_reset_token($$$)
{
    my ( $db, $email, $password_reset_link ) = @_;

    my $full_name;
    eval {
        my $user = MediaWords::DBI::Auth::Info::user_info( $db, $email );
        $full_name = $user->full_name();
    };
    if ( $@ )
    {
        WARN "Unable to fetch user $email: $@";
        $full_name = 'Nonexistent user';
    }

    # If user was not found, send an email to a random address anyway to avoid timing attach
    $password_reset_link = _generate_password_reset_token( $db, $email, $password_reset_link );
    unless ( $password_reset_link )
    {
        $email               = 'nowhere@mediacloud.org';
        $password_reset_link = 'password reset link';
    }

    eval {

        my $message = MediaWords::Util::Mail::Message::Templates::AuthResetPasswordMessage->new(
            {
                to                 => $email,
                full_name          => $full_name,
                password_reset_url => $password_reset_link,
            }
        );
        unless ( MediaWords::Util::Mail::send_email( $message ) )
        {
            die "Unable to send email message.";
        }

    };
    if ( $@ )
    {
        WARN "Unable to send password reset email: $@";
        die 'Unable to send password reset email.';
    }
}

1;
