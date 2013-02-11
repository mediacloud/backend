package MediaWords::DBI::Auth;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

#
# Authentication helpers
#

use strict;
use warnings;

use Crypt::SaltedHash;
use MediaWords::Util::Mail;
use POSIX qw(strftime);

use Data::Dumper;

# Fetch a hash of basic user information (email, full name, notes)
sub user_info($$)
{
    my ( $db, $email ) = @_;

    # Fetch readonly information about the user
    my $userinfo = $db->query(
        <<"EOF",
        SELECT users_id,
               email,
               full_name,
               notes
        FROM auth_users
        WHERE email = ?
        LIMIT 1
EOF
        $email
    )->hash;
    if ( !( ref( $userinfo ) eq 'HASH' and $userinfo->{ users_id } ) )
    {
        say STDERR 'Unable to find user ' . $email . ' in the database.';
        return 0;
    }

    return $userinfo;
}

# Change password; returns error message on failure, empty string on success
sub change_password($$$$$)
{
    my ( $db, $email, $password_old, $password_new, $password_new_repeat ) = @_;

    if ( !( $password_old && $password_new && $password_new_repeat ) )
    {
        return 'To change the password, please enter an old ' . 'password and then repeat the new password twice.';
    }

    if ( $password_new ne $password_new_repeat )
    {
        return 'Passwords do not match.';
    }

    if ( $password_old eq $password_new )
    {
        return 'Old and new passwords are the same.';
    }

    if ( length( $password_new ) < 8 or length( $password_new ) > 120 )
    {
        return 'Password must be 8 to 120 characters in length.';
    }

    if ( $password_new eq $email )
    {
        return 'New password is your email address; don\'t cheat!';
    }

    # Validate old password (password hash is located in $c->user->password, but fetch
    # the hash from the database again because that hash might be outdated (e.g. if the
    # password has been changed already))
    my $db_password_old = $db->query(
        <<"EOF",
        SELECT users_id,
               email,
               password_hash
        FROM auth_users
        WHERE email = ?
        LIMIT 1
EOF
        $email
    )->hash;

    if ( !( ref( $db_password_old ) eq 'HASH' and $db_password_old->{ users_id } ) )
    {
        return 'Unable to find the user in the database.';
    }
    $db_password_old = $db_password_old->{ password_hash };

    # Determine salt and hash type
    my $config = MediaWords::Util::Config::get_config;

    my $salt_len = $config->{ 'Plugin::Authentication' }->{ 'users' }->{ 'credential' }->{ 'password_salt_len' };
    if ( !$salt_len )
    {
        $salt_len = 0;
    }

    my $hash_type = $config->{ 'Plugin::Authentication' }->{ 'users' }->{ 'credential' }->{ 'password_hash_type' };
    if ( !$hash_type )
    {
        return 'Unable to determine the password hashing algorithm.';
    }

    if ( !Crypt::SaltedHash->validate( $db_password_old, $password_old, $salt_len ) )
    {
        return 'Old password is incorrect.';
    }

    # Hash the password
    my $csh = Crypt::SaltedHash->new( algorithm => $hash_type, salt_len => $salt_len );
    $csh->add( $password_new );
    my $password_new_hash = $csh->generate;
    if ( !$password_new_hash )
    {
        return 'Unable to hash a new password.';
    }
    if ( !Crypt::SaltedHash->validate( $password_new_hash, $password_new, $salt_len ) )
    {
        return 'New password hash has been generated, but it does not validate.';
    }

    # Set the password
    $db->query(
        <<"EOF",
        UPDATE auth_users
        SET password_hash = ?
        WHERE email = ?
EOF
        $password_new_hash, $email
    );

    # Send email
    my $now           = strftime( "%a, %d %b %Y %H:%M:%S %z", localtime( time() ) );
    my $email_subject = 'Your password has been changed';
    my $email_message = <<"EOF";
Your Media Cloud password has been changed on $now.

If you made this change, no need to reply - you're all set.

If you did not request this change, please contact Media Cloud support at
www.mediacloud.org.
EOF

    if ( !MediaWords::Util::Mail::send( $email, $email_subject, $email_message ) )
    {
        return 'The password has been changed, but I was unable to send an email notifying you about the change.';
    }

    # Success
    return '';
}

1;
