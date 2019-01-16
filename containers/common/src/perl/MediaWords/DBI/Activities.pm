
=head1 NAME

C<MediaWords::DBI::Activities> - Package to log various activities (story
edits, media edits, etc.)

=head1 NOTES

=over 4

=item * It is advised to manually C<BEGIN TRANSACTION> before logging an
activity and C<COMMIT> after the logging is successful. C<__log_activity()>
doesn't initiate its own transaction in order to not disturb the transaction
that the caller of might have initiated.

=back

=head1 SYNOPSIS

=head2 Logging a single activity

    $c->dbis->begin_work;

    # Snapshot the topic
    create_snapshot();

    # Log activity
    my $change = {
        'field' => 'description',
        'old_value' => $old_description,
        'new_value' => $new_description
    };
    unless (
        MediaWords::DBI::Activities::__log_activity(
            $c->dbis, 'tm_snapshot_topic', $c->user->username, $stories_id, $reason, $change
        )
      )
    {
        $c->dbis->rollback;
        die "Unable to log addition of new tags.\n";
    }

    $c->dbis->commit;

=head2 Logging a system activity from a CLI script

    #!/usr/bin/env perl

    sub main()
    {
        my $db = MediaWords::DB::connect_to_db;

        my $topics_id = 12345;

        # Do whatever the script needs to do
        do_something_important($db);

        # Log the activity that was just done
        my $options = {
            dedup_stories          => 1
            import_only            => 0
            cache_broken_downloads => 0
        };

        # Log activity that just happened
        unless ( MediaWords::DBI::Activities::log_system_activity(
            $db,
            'something_important',
            $topics_id,
            $options ) )
        {
            die "Unable to log the 'something_important' activity.";
        }

        DEBUG "All good.";
    }

    main();

=cut

package MediaWords::DBI::Activities;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Array::Compare;
use MediaWords::Util::ParseJSON;

=head1 LIST OF ACTIVITIES

=head2 (static) C<%ACTIVITIES>

List of available activities that can be logged, their descriptions, pointers
to what the object ID refers to and parameters.

All activities that are logged *must* be added to this hash.

To add a new activity, add a sub-entry to this hash.

=cut

Readonly::Hash my %ACTIVITIES => {

    'tm_snapshot_topic' => {
        description => 'Snapshot topic',
        object_id   => {
            description => 'Topic ID for which the snapshot was made',
            references  => 'topics.topics_id'
        },
        parameters => {}
    },

    'tm_mine_topic' => {
        description => 'Mine topic',
        object_id   => {
            description => 'Topic ID that was mined',
            references  => 'topics.topics_id'
        },
        parameters => {
            'skip_post_processing' => { description => 'skip social media and snapshot' },
            'import_only'          => { description => 'only run import_seed_urls and import_query_story_search and exit' },
            'cache_broken_downloads' => { description => 'speed up fixing broken downloads' },
            'skip_outgoing_foreign_rss_links' =>
              { description => 'skip slow process of adding links from foreign_rss_links media' },
            'test_mode' => { description => 'run in test mode -- do not try to queue extractions' }
        }
    },

};

=head1 METHODS

=head2 (static) C<__log_activity($db, $activity_name, $user, $object_id, $reason, $description_hash)>

Log activity.

Parameters:

=over 4

=item * C<$db> - Reference to the database object.

=item * C<$activity_name> - Activity name from the C<%ACTIVITIES> hash, e.g.
C<tm_mine_topic>.

=item * C<$user> - User that initiated the activity, either: a) user's email,
e.g. C<jdoe@cyber.law.harvard.edu>, or b) system username if the activity was
initiated from the shell and not from the web UI, e.g. C<system:jdoe>.

=item * C<$object_id> - integer ID of an object (e.g. story ID, media ID) that
was modified by the activity. Pass 0 if there's no objects to refer to.

=item * C<$reason> - Reason the activity was made. Pass empty string ('') if
there was no reason provided.

=item * C<$description_hash> - hashref of miscellaneous parameters that
describe the activity, e.g.:

    {
        'field' => 'description',   # Field that was edited
        'old_value' => 'Foo...',    # Old value of the field
        'new_value' => 'Bar!'       # New value of the field
    }

=back

Returns 1 if the activity was logged. Returns 0 on error.

=cut

sub __log_activity($$$$$$)
{
    my ( $db, $activity_name, $user, $object_id, $reason, $description_hash ) = @_;

    eval {

        # Validate activity name
        unless ( exists $ACTIVITIES{ $activity_name } )
        {
            die "Activity '$activity_name' is not configured.";
        }

        # Check if user making a change exists (unless it's a system user)
        unless ( $user =~ /^system:.+?$/ )
        {
            my $user_exists = $db->query(
                <<"EOF",
                SELECT auth_users_id
                FROM auth_users
                WHERE email = ?
                LIMIT 1
EOF
                $user
            )->hash;
            unless ( ref( $user_exists ) eq 'HASH' and $user_exists->{ auth_users_id } )
            {
                die "User '$user' does not exist.";
            }
        }

        # Encode description into JSON
        my $description_json = __encode_activity_description( $activity_name, $description_hash );
        unless ( $description_json )
        {
            die "Unable to encode activity description to JSON: $!";
        }

        # Save
        $db->query(
            <<EOF,
            INSERT INTO activities (name, user_identifier, object_id, reason, description_json)
            VALUES (?, ?, ?, ?, ?)
EOF
            $activity_name, $user, $object_id, $reason, $description_json
        );
    };
    if ( $@ )
    {
        # Writing the change failed
        ERROR "Writing activity failed: $@";
        return 0;
    }

    return 1;
}

=head2 (static) C<log_system_activity($db, $activity_name, $object_id, $description_hash)>

Log system activity (the one that was initiated on the shell and not from the
web UI).

See C<__log_activity()> for the description of other parameters of this
subroutine.

Returns 1 if the activity was logged. Returns 0 on error.

=cut

sub log_system_activity($$$$)
{
    my ( $db, $activity_name, $object_id, $description_hash ) = @_;

    my $username = getpwuid( $< ) || 'unknown';

    return __log_activity( $db, $activity_name, 'system:' . $username, $object_id, '', $description_hash );
}

=head1 HELPERS

The helpers described below are mainly used by the web UI that lists the
activities from the database.

=head2 (static) C<__encode_activity_description($activity_name, $description_hash)>

Validates and encodes an activity description hash to a string value (JSON in
the current implementation).

Parameters:

=over 4

=item * C<$activity_name> - Activity name from the C<%ACTIVITIES> hash, e.g.
C<tm_mine_topic>.

=item * C<$description_hash> - hashref of miscellaneous parameters that
describe the activity.

=back

Returns a (JSON-encoded) string activity description.

C<die()>s on error.

=cut

sub __encode_activity_description($$)
{
    my ( $activity_name, $description_hash ) = @_;

    unless ( $description_hash )
    {
        $description_hash = {};
    }
    unless ( ref $description_hash eq 'HASH' )
    {
        die "Invalid activity description (" . ref( $description_hash ) . "): " . Dumper( $description_hash );
    }
    my $activity            = $ACTIVITIES{ $activity_name };
    my @expected_parameters = sort( keys %{ $activity->{ parameters } } );
    my @actual_parameters   = sort( keys %{ $description_hash } );

    my $comp = Array::Compare->new;

    unless ( $comp->compare( \@expected_parameters, \@actual_parameters ) )
    {
        die "Expected parameters: " .
          join( ' ', @expected_parameters ) . "\n" . "Actual parameters: " .
          join( ' ', @actual_parameters );
    }

    my $description_json = MediaWords::Util::ParseJSON::encode_json( $description_hash );
    unless ( $description_json )
    {
        die "Unable to encode activity description to JSON: $!";
    }

    return $description_json;
}

1;
