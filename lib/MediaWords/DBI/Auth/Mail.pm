package MediaWords::DBI::Auth::Mail;

#
# Emails to new / existing users
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

use MediaWords::Util::Mail;
use POSIX qw(strftime);

sub send_password_changed_email($)
{
    my $email = shift;

    # Send email
    my $now           = strftime( "%a, %d %b %Y %H:%M:%S %z", localtime( time() ) );
    my $email_subject = 'Your password has been changed';
    my $email_message = <<"EOF";
Your Media Cloud password has been changed on $now.

If you made this change, no need to reply - you're all set.

If you did not request this change, please contact Media Cloud support at
www.mediacloud.org.
EOF

    unless ( MediaWords::Util::Mail::send( $email, $email_subject, $email_message ) )
    {
        die 'The password has been changed, but I was unable to send an email notifying you about the change.';
    }
}

sub send_password_reset_email($$)
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

sub send_new_user_email($$)
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

http://mediacloud.org/get-involved

If you have any questions about the Media Cloud project, tools, or data, please join
the mediacloud-users list described at the above link and ask them there.  We
encourage you to join the mediacloud-users list just to share how you are using
Media Cloud even if you do not have any specific questions.  If you have questions
about your account or other private questions email info\@mediacloud.org.

EOF

    unless ( MediaWords::Util::Mail::send( $email, $email_subject, $email_message ) )
    {
        die 'The user was created, but I was unable to send you an activation email.';
    }
}

1;
