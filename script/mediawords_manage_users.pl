#!/usr/bin/env perl

# CLI user administration
#
# Usage:
#   ./script/run_with_carton.sh ./script/mediawords_manage_users.pl
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use Getopt::Long qw(:config pass_through);
use Term::Prompt;
use MediaWords::DBI::Auth;
use MediaWords::Util::Config;
use Term::ReadKey;

use MediaWords;    # load Catalyst's configuration incl. the password hashing algorithm

# Helper to read passwords from CLI without showing them
# (http://stackoverflow.com/a/701234/200603 plus http://search.cpan.org/dist/TermReadKey/ReadKey.pm)
sub _read_password
{

    # Start reading the keys
    my $password = '';

    ReadMode( 2 );    # cooked mode with echo off.

    # This will continue until the Enter key is pressed (decimal value of 10)
    while ( ord( my $key = ReadKey( 0 ) ) != 10 )
    {

        # For all value of ord($key) see http://www.asciitable.com/
        if ( ord( $key ) == 127 || ord( $key ) == 8 )
        {

            # Delete / Backspace was pressed
            # 1. Remove the last char from the password
            chop( $password );

            # 2. Move the cursor back by one, print a blank character, move the cursor back by one
            print "\b \b";
        }
        elsif ( ord( $key ) < 32 )
        {

            # Do nothing with control characters
        }
        else
        {
            $password .= $key;
        }
    }

    ReadMode( 0 );    # reset the terminal once we are done

    print STDERR "\n";

    return $password;
}

# Add user; returns 0 on success, 1 on error
sub user_add($)
{
    my ( $db ) = @_;

    my $user_email       = undef;
    my $user_full_name   = '';
    my $user_notes       = '';
    my $user_is_inactive = 0;
    my $user_roles       = '';
    my $user_password    = undef;

    my Readonly $user_add_usage =
      "Usage: $0" . ' --action=add' . ' --email=jdoe@cyber.law.harvard.edu' . ' --full_name="John Doe"' .
      ' [--notes="Media Cloud developer."]' . ' [--inactive]' . ' [--roles="query-create,media-edit,stories-edit"]' .
      ' [--password="correct horse battery staple"]';

    GetOptions(
        'email=s'     => \$user_email,
        'full_name=s' => \$user_full_name,
        'notes:s'     => \$user_notes,
        'inactive'    => \$user_is_inactive,
        'roles:s'     => \$user_roles,
        'password:s'  => \$user_password
    ) or die "$user_add_usage\n";
    die "$user_add_usage\n" unless ( $user_email and $user_full_name );

    # Roles array
    my @user_roles = split( ',', $user_roles );
    my @user_role_ids;
    foreach my $user_role ( @user_roles )
    {
        my $user_role_id = MediaWords::DBI::Auth::role_id_for_role( $db, $user_role );
        if ( !$user_role_id )
        {
            say STDERR "Role '$user_role' was not found.";
            return 1;
        }

        push( @user_role_ids, $user_role_id );
    }

    # Read password if not set
    my $user_password_repeat = undef;
    if ( $user_password )
    {
        $user_password_repeat = $user_password;
    }
    else
    {
        while ( !$user_password )
        {
            print "Enter password: ";
            $user_password = _read_password();
        }
        while ( !$user_password_repeat )
        {
            print "Repeat password: ";
            $user_password_repeat = _read_password();
        }
    }

    # Add the user
    my $add_user_error_message =
      MediaWords::DBI::Auth::add_user_or_return_error_message( $db, $user_email, $user_full_name, $user_notes,
        \@user_role_ids, ( !$user_is_inactive ),
        $user_password, $user_password_repeat );
    if ( $add_user_error_message )
    {
        say STDERR "Error while trying to add user: $add_user_error_message";
        return 1;
    }

    say STDERR "User with email address '$user_email' was successfully added.";

    return 0;
}

# Remove user; returns 0 on success, 1 on error
sub user_remove($)
{
    my ( $db ) = @_;

    my $user_email = undef;

    my Readonly $user_remove_usage = "Usage: $0" . ' --action=remove' . ' --email=jdoe@cyber.law.harvard.edu';

    GetOptions( 'email=s' => \$user_email, ) or die "$user_remove_usage\n";
    die "$user_remove_usage\n" unless ( $user_email );

    # Add the user
    # Delete user
    my $delete_user_error_message = MediaWords::DBI::Auth::delete_user_or_return_error_message( $db, $user_email );
    if ( $delete_user_error_message )
    {
        say STDERR "Error while trying to remove user: $delete_user_error_message";
        return 1;
    }

    say STDERR "User with email address '$user_email' was removed successfully.";

    return 0;
}

# User manager
sub main
{
    my $action        = '';                                                       # which action to take
    my @valid_actions = qw/add remove modify activate deactivate reset roles/;    # valid roles

    my Readonly $usage = "Usage: $0" . ' --action=' . join( '|', @valid_actions ) . ' ...';

    GetOptions( 'action=s' => \$action, ) or die "$usage\n";
    die "$usage\n" unless ( grep { $_ eq $action } @valid_actions );

    binmode( STDOUT, ":utf8" );
    binmode( STDERR, ":utf8" );

    my $db = MediaWords::DB::connect_to_db() || die DBIx::Simple::MediaWords->error;

    if ( $action eq 'add' )
    {

        # Add user
        return user_add( $db );

    }
    elsif ( $action eq 'remove' )
    {

        # Remove user
        return user_remove( $db );
    }
}

exit main();
