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

sub _send_password_reset_email($$)
{
    my ( $email, $password_reset_link ) = @_;

    my $email_subject = 'Password reset link';
    my $email_message = <<"EOF";
Someone (hopefully that was you) has requested a link to change your password,
and you can do this through the link below:

$password_reset_link

Your password won't change until you access the link above and create a new one.

If you didn't request this, please ignore this email or contact Media Cloud
support at www.mediacloud.org.
EOF

    unless ( MediaWords::Util::Mail::send( $email, $email_subject, $email_message ) )
    {
        die 'The password has been changed, but I was unable to send an email notifying you about the change.';
    }
}

# Prepare for password reset by emailing the password reset token; die()s on error
sub send_password_reset_token($$$)
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

    eval { _send_password_reset_email( $email, $password_reset_link ); };
    if ( $@ )
    {
        my $error_message = "Unable to send email to user: $@";
        die $error_message;
    }
}

1;
