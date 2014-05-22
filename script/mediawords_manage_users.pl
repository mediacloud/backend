#!/usr/bin/env perl
#
# CLI user manager
#
#
# Usage
# =====
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl --help          # manager's help
#     or
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl --action=...    # action's help
#
# Add user
# --------
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
#         --action=add \
#         --email=jdoe@cyber.law.harvard.edu \
#         --full_name="John Doe" \
#         --notes="Media Cloud developer." \
#         [--inactive] \
#         --roles="query-create,media-edit,stories-edit" \
#         [--password="correct horse battery staple"] \
#         [--weekly_requests_limit=2000] \
#         [--weekly_requested_items_limit=10000]
#
#     Notes:
#     * Skip the `--password` parameter to read the password from STDIN.
#     * Pass the `--inactive` parameter to make the user inactive initially.
#
# Modify user
# -----------
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
#         --action=modify \
#         --email=jdoe@cyber.law.harvard.edu \
#         [--full_name="John Doe"] \
#         [--notes="Media Cloud developer."] \
#         [--active|--inactive] \
#         [--roles="query-create,media-edit,stories-edit"] \
#         [--password="correct horse battery staple" | --set-password] \
#         [--weekly_requests_limit=2000] \
#         [--weekly_requested_items_limit=10000]
#
#     Notes:
#     * Pass only those parameters that you want to change; skip the ones that you want to leave inact.
#     * You can change the user's password either by:
#         * passing the new password as the value of `--password`, or
#         * proving the `--set-password` parameter to read the new password from STDIN.
#
# Delete user
# -----------
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
#         --action=delete \
#         --email=jdoe@cyber.law.harvard.edu
#
# Show user information
# ---------------------
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
#         --action=show \
#         --email=jdoe@cyber.law.harvard.edu
#
# List all users
# --------------
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
#         --action=list
#
# List all user roles
# -------------------
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
#         --action=roles
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Getopt::Long qw(:config pass_through);
use Term::Prompt;
use MediaWords::DBI::Auth;
use MediaWords::Util::Config;
use Term::ReadKey;

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
            # 1. Delete the last char from the password
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

    my $user_email                        = undef;
    my $user_full_name                    = '';
    my $user_notes                        = '';
    my $user_is_inactive                  = 0;
    my $non_public_api_access             = 0;
    my $user_roles                        = '';
    my $user_password                     = undef;
    my $user_weekly_requests_limit        = undef;
    my $user_weekly_requested_items_limit = undef;

    my Readonly $user_add_usage = <<"EOF";
Usage: $0 --action=add \
    --email=jdoe\@cyber.law.harvard.edu \
    --full_name="John Doe" \
    [--notes="Media Cloud developer."] \
    [--inactive] \
    [--non_public_api_access ] \
    [--roles="query-create,media-edit,stories-edit"] \
    [--password="correct horse battery staple"] \
    [--weekly_requests_limit=2000] \
    [--weekly_requested_items_limit=10000]
EOF

    GetOptions(
        'email=s'                        => \$user_email,
        'full_name=s'                    => \$user_full_name,
        'notes:s'                        => \$user_notes,
        'inactive'                       => \$user_is_inactive,
        'non_public_api_access'          => \$non_public_api_access,
        'roles:s'                        => \$user_roles,
        'password:s'                     => \$user_password,
        'weekly_requests_limit:i'        => \$user_weekly_requests_limit,
        'weekly_requested_items_limit:i' => \$user_weekly_requested_items_limit
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
    my $add_user_error_message = MediaWords::DBI::Auth::add_user_or_return_error_message(
        $db, $user_email, $user_full_name,
        $user_notes, \@user_role_ids, ( !$user_is_inactive ),
        $user_password,              $user_password_repeat, $non_public_api_access,
        $user_weekly_requests_limit, $user_weekly_requested_items_limit
    );
    if ( $add_user_error_message )
    {
        say STDERR "Error while trying to add user: $add_user_error_message";
        return 1;
    }

    say STDERR "User with email address '$user_email' was successfully added.";

    return 0;
}

# Modify user; returns 0 on success, 1 on error
sub user_modify($)
{
    my ( $db ) = @_;

    my $user_email                        = undef;
    my $user_full_name                    = undef;
    my $user_notes                        = undef;
    my $user_is_active                    = undef;
    my $user_is_inactive                  = undef;
    my $user_roles                        = undef;
    my $user_password                     = undef;
    my $user_set_password                 = undef;
    my $user_weekly_requests_limit        = undef;
    my $user_weekly_requested_items_limit = undef;

    my Readonly $user_modify_usage = <<"EOF";
Usage: $0 --action=modify \
    --email=jdoe\@cyber.law.harvard.edu \
    [--full_name="John Doe"] \
    [--notes="Media Cloud developer."] \
    [--active|--inactive] \
    [--roles="query-create,media-edit,stories-edit"] \
    [--password="correct horse battery staple" | --set-password] \
EOF

    GetOptions(
        'email=s'                        => \$user_email,
        'full_name:s'                    => \$user_full_name,
        'notes:s'                        => \$user_notes,
        'active'                         => \$user_is_active,
        'inactive'                       => \$user_is_inactive,
        'roles:s'                        => \$user_roles,
        'password:s'                     => \$user_password,
        'set-password'                   => \$user_set_password,
        'weekly_requests_limit:i'        => \$user_weekly_requests_limit,
        'weekly_requested_items_limit:i' => \$user_weekly_requested_items_limit
    ) or die "$user_modify_usage\n";
    die "$user_modify_usage\n" unless ( $user_email );

    # Fetch default information about the user
    my $db_user = MediaWords::DBI::Auth::user_info( $db, $user_email );
    my $db_user_roles = MediaWords::DBI::Auth::user_auth( $db, $user_email );

    unless ( $db_user and $db_user_roles )
    {
        say STDERR "Unable to find user '$user_email' in the database.";
        return 1;
    }

    # Check if anything has to be changed
    unless ( defined $user_full_name
        or defined $user_notes
        or defined $user_is_active
        or defined $user_is_inactive
        or defined $user_roles
        or defined $user_password
        or defined $user_set_password
        or defined $user_weekly_requests_limit
        or defined $user_weekly_requested_items_limit )
    {
        say STDERR "Nothing has to be changed.";
        die "$user_modify_usage\n";
    }

    # Hash with user values that should be put back into database
    my %modified_user;
    $modified_user{ email } = $user_email;

    # Overwrite the information if provided as parameters
    $modified_user{ full_name } = ( $user_full_name ? $user_full_name : $db_user->{ full_name } );
    $modified_user{ notes }     = ( $user_notes     ? $user_notes     : $db_user->{ notes } );

    if ( defined $user_is_active )
    {
        $modified_user{ active } = 1;
    }
    elsif ( defined $user_is_inactive )
    {
        $modified_user{ active } = 0;
    }
    else
    {
        $modified_user{ active } = $db_user->{ active };
    }

    # Roles array
    $modified_user{ roles } = ( $user_roles ? [ split( ',', $user_roles ) ] : $db_user_roles->{ roles } );

    my @user_role_ids;
    foreach my $user_role ( @{ $modified_user{ roles } } )
    {
        my $user_role_id = MediaWords::DBI::Auth::role_id_for_role( $db, $user_role );
        if ( !$user_role_id )
        {
            say STDERR "Role '$user_role' was not found.";
            return 1;
        }

        push( @user_role_ids, $user_role_id );
    }
    $modified_user{ role_ids } = \@user_role_ids;

    # Set / read the password (if needed)
    $modified_user{ password }        = '';
    $modified_user{ password_repeat } = '';
    if ( $user_password )
    {
        $modified_user{ password } = $modified_user{ password_repeat } = $user_password;
    }
    elsif ( $user_set_password )
    {
        while ( !$modified_user{ password } )
        {
            print "Enter password: ";
            $modified_user{ password } = _read_password();
        }
        while ( !$modified_user{ password_repeat } )
        {
            print "Repeat password: ";
            $modified_user{ password_repeat } = _read_password();
        }
    }

    # Modify (update) user
    my $update_user_error_message = MediaWords::DBI::Auth::update_user_or_return_error_message(
        $db,
        $modified_user{ email },
        $modified_user{ full_name },
        $modified_user{ notes },
        $modified_user{ role_ids },
        $modified_user{ active },
        $modified_user{ password },
        $modified_user{ password_repeat },
        $user_weekly_requests_limit,
        $user_weekly_requested_items_limit
    );
    if ( $update_user_error_message )
    {
        say STDERR "Error while trying to modify user: $update_user_error_message";
        return 1;
    }

    say STDERR "User with email address '$user_email' was successfully modified.";

    return 0;
}

# Delete user; returns 0 on success, 1 on error
sub user_delete($)
{
    my ( $db ) = @_;

    my $user_email = undef;

    my Readonly $user_delete_usage = "Usage: $0" . ' --action=delete' . ' --email=jdoe@cyber.law.harvard.edu';

    GetOptions( 'email=s' => \$user_email, ) or die "$user_delete_usage\n";
    die "$user_delete_usage\n" unless ( $user_email );

    # Add the user
    # Delete user
    my $delete_user_error_message = MediaWords::DBI::Auth::delete_user_or_return_error_message( $db, $user_email );
    if ( $delete_user_error_message )
    {
        say STDERR "Error while trying to delete user: $delete_user_error_message";
        return 1;
    }

    say STDERR "User with email address '$user_email' was deleted successfully.";

    return 0;
}

# List users; returns 0 on success, 1 on error
sub users_list($)
{
    my ( $db ) = @_;

    my Readonly $user_list_usage = "Usage: $0" . ' --action=list';

    GetOptions() or die "$user_list_usage\n";

    # Fetch list of users
    my $users = MediaWords::DBI::Auth::all_users( $db );

    unless ( $users )
    {
        say STDERR "Unable to fetch a list of users from the database.";
        return 1;
    }

    foreach my $user ( @{ $users } )
    {
        say $user->{ email };
    }

    return 0;
}

# Show user information; returns 0 on success, 1 on error
sub user_show($)
{
    my ( $db ) = @_;

    my $user_email = undef;

    my Readonly $user_show_usage = "Usage: $0" . ' --action=show' . ' --email=jdoe@cyber.law.harvard.edu';

    GetOptions( 'email=s' => \$user_email, ) or die "$user_show_usage\n";
    die "$user_show_usage\n" unless ( $user_email );

    # Fetch information about the user
    my $db_user = MediaWords::DBI::Auth::user_info( $db, $user_email );
    my $db_user_roles = MediaWords::DBI::Auth::user_auth( $db, $user_email );

    unless ( $db_user and $db_user_roles )
    {
        say STDERR "Unable to find user '$user_email' in the database.";
        return 1;
    }

    say "User ID:\t" . $db_user->{ auth_users_id };
    say "Email (username):\t" . $db_user->{ email };
    say "Full name:\t" . $db_user->{ full_name };
    say "Notes:\t" . $db_user->{ notes };
    say "Active:\t" . ( $db_user->{ active } ? 'yes' : 'no' );
    say "Roles:\t" . join( ',', @{ $db_user_roles->{ roles } } );
    say "Weekly requests limit: " . $db_user->{ weekly_requests_limit };
    say "Weekly requested items limit: " . $db_user->{ weekly_requested_items_limit };

    return 0;
}

# List user roles; returns 0 on success, 1 on error
sub user_roles($)
{
    my ( $db ) = @_;

    my Readonly $user_roles_usage = "Usage: $0" . ' --action=roles';

    GetOptions() or die "$user_roles_usage\n";

    # Fetch roles
    my $roles = MediaWords::DBI::Auth::all_user_roles( $db );

    unless ( $roles )
    {
        say STDERR "Unable to fetch a list of user roles from the database.";
        return 1;
    }

    foreach my $role ( @{ $roles } )
    {
        say $role->{ role } . "\t" . $role->{ description };
    }

    return 0;
}

# User manager
sub main
{
    my $action        = '';                                       # which action to take
    my @valid_actions = qw/add modify delete show list roles/;    # valid actions

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
    elsif ( $action eq 'modify' )
    {

        # Modify (update) user
        return user_modify( $db );
    }
    elsif ( $action eq 'delete' )
    {

        # Delete user
        return user_delete( $db );
    }
    elsif ( $action eq 'list' )
    {

        # List users
        return users_list( $db );
    }
    elsif ( $action eq 'show' )
    {

        # Show user information
        return user_show( $db );
    }
    elsif ( $action eq 'roles' )
    {

        # List user roles
        return user_roles( $db );
    }
    else
    {
        die "$usage\n";
        return 1;
    }
}

exit main();
