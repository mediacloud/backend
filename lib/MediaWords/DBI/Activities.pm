
=head1 NAME

C<MediaWords::DBI::Activities> - Package to log various activities (story
edits, media edits, etc.)

=head1 NOTES

=over 4

=item * It is advised to manually C<BEGIN TRANSACTION> before logging an
activity and C<COMMIT> after the logging is successful. C<log_activity()>
doesn't initiate its own transaction in order to not disturb the transaction
that the caller of might have initiated.

=back

=head1 SYNOPSIS

=head2 Logging a single activity from web UI's controller

    $c->dbis->dbh->begin_work;

    # Save story edit
    save_story_edit();

    # Log activity
    my $change = {
        'field' => 'description',
        'old_value' => $old_description,
        'new_value' => $new_description
    };
    unless (
        MediaWords::DBI::Activities::log_activity(
            $c->dbis, 'story_edit', $c->user->username, $stories_id, $reason, $change
        )
      )
    {
        $c->dbis->dbh->rollback;
        die "Unable to log addition of new tags.\n";
    }

    $c->dbis->dbh->commit;

=head2 Logging a system activity from a CLI script

    #!/usr/bin/env perl

    sub main()
    {
        my $db = MediaWords::DB::connect_to_db;

        my $controversies_id = 12345;

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
            $controversies_id,
            $options ) )
        {
            die "Unable to log the 'something_important' activity.";
        }

        say STDERR "All good.";
    }

    main();

=cut
package MediaWords::DBI::Activities;

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use JSON;

=head1 LIST OF ACTIVITIES

=head2 (static) C<%ACTIVITIES>

List of available activities that can be logged, their descriptions, pointers
to what the object ID refers to and parameters.

All activities that are logged *must* be added to this hash.

To add a new activity, add a sub-entry to this hash using the example below.

Example:

    # Activity name that identifies the activity:
    'cm_remove_story_from_controversy' => {

        # Human-readable description of the activity that is going to be presented
        # in the web UI
        description => 'Remove story from a controversy',

        # Logged activity may provide an integer "object ID" which identifies the
        # object that was changed by the activity.
        #
        # For example, an object ID should probably contain a story ID
        # (stories.stories_id) if the activity is a story edit.
        object_id   => {

            # Human-readable description of the object ID
            description => 'Controversy ID from which the story was removed',

            # (optional) Table and column that the object ID references
            references  => 'controversies.controversies_id'
        },

        # Logged activity may provide other parameters that describe the particular
        # activity in better detail. These parameters are going to be encoded in
        # JSON and stored as an activity's description.
        parameters => {

            # JSON key of the parameter
            'stories_id' => {

                # Human-readable description of the value of the parameter
                description => 'Story ID that was removed from the controversy',

                # (optional) Table and column that the value of the parameter
                # references
                references  => 'stories.stories_id'
            },
            <...>
        }
    },
    <...>

=cut
Readonly::Hash my %ACTIVITIES => {

    'cm_remove_story_from_controversy' => {
        description => 'Remove story from a controversy',
        object_id   => {
            description => 'Controversy ID from which the story was removed',
            references  => 'controversies.controversies_id'
        },
        parameters => {
            'stories_id' => {
                description => 'Story ID that was removed from the controversy',
                references  => 'stories.stories_id'
            },
            'cdts_id' => {
                description => 'Controversy dump time slice',
                references  => 'controversy_dump_time_slices.controversy_dump_time_slices_id'
            }
        }
    },

    'cm_media_merge' => {
        description => 'Merge medium into another medium',
        object_id   => {
            description => 'Controversy ID in which the media merge was made',
            references  => 'controversies.controversies_id'
        },
        parameters => {
            'media_id' => {
                description => 'Media ID that was merged',
                references  => 'media.media_id'
            },
            'to_media_id' => {
                description => 'Media ID that the medium was merged into',
                references  => 'media.media_id'
            },
            'cdts_id' => {
                description => 'Controversy dump time slice',
                references  => 'controversy_dump_time_slices.controversy_dump_time_slices_id'
            }
        }
    },

    'cm_story_merge' => {
        description => 'Merge story into another story',
        object_id   => {
            description => 'Controversy ID in which the story merge was made',
            references  => 'controversies.controversies_id'
        },
        parameters => {
            'stories_id' => {
                description => 'Story ID that was merged',
                references  => 'stories.stories_id'
            },
            'to_stories_id' => {
                description => 'Story ID that the story was merged into',
                references  => 'stories.stories_id'
            },
            'cdts_id' => {
                description => 'Controversy dump time slice',
                references  => 'controversy_dump_time_slices.controversy_dump_time_slices_id'
            }
        }
    },

    'cm_dump_controversy' => {
        description => 'Dump controversy',
        object_id   => {
            description => 'Controversy ID for which the dump was made',
            references  => 'controversies.controversies_id'
        },
        parameters => {
            'controversy_opt' =>
              { description => 'Options that were passed as arguments to the "mediawords_dump_controversy.pl" script' }
        }
    },

    'cm_mine_controversy' => {
        description => 'Mine controversy',
        object_id   => {
            description => 'Controversy ID that was mined',
            references  => 'controversies.controversies_id'
        },
        parameters => {
            'dedup_stories'          => { description => 'FIXME' },
            'import_only'            => { description => 'FIXME' },
            'cache_broken_downloads' => { description => 'FIXME' }
        }
    },

    'cm_search_tag_run' => {
        description => 'Run the "search and tag controversy stories" script',
        object_id   => {
            description => 'Controversy ID for which the stories were re-tagged',
            references  => 'controversies.controversies_id'
        },
        parameters => {
            'controversy_name' => {
                description =>
'Controversy name that was passed as an argument to the "mediawords_search_and_tag_controversy_stories.pl" script'
            }
        }
    },

    'cm_search_tag_change' => {
        description => 'Change the tag while running the "search and tag controversy stories" script',
        object_id   => {
            description => 'Controversy ID for which the stories were re-tagged',
            references  => 'controversies.controversies_id'
        },
        parameters => {
            'regex'      => { description => 'Regular expression that was used while re-tagging' },
            'stories_id' => {
                description => 'Story ID that was re-tagged',
                references  => 'stories_tags_map.stories_id'    # in this case
            },
            'tag_sets_id' => {
                description => 'Tag set\'s ID',
                references  => 'tag_sets.tag_sets_id'
            },
            'tags_id' => {
                description => 'Tag\'s ID',
                references  => 'stories_tags_map.tags_id'       # in this case
            },
            'tag' => {
                description => 'Tag name',
                references  => 'tags.tag'
            }
        }
    },

    'story_edit' => {
        description => 'Edit a story',
        object_id   => {
            description => 'Story ID that was edited',
            references  => 'stories.stories_id'
        },
        parameters => {
            'field' => {
                description => 'Database field that was edited (if the field is "_tags", a story had a tag added / removed)'
            },
            'old_value' => { description => 'Old value of the database field that was edited' },
            'new_value' => { description => 'New value of the database field that was edited' }
        }
    },

    'media_edit' => {
        description => 'Edit a medium',
        object_id   => {
            description => 'Media ID that was edited',
            references  => 'media.media_id'
        },
        parameters => {
            'field'     => { description => 'Database field that was edited' },
            'old_value' => { description => 'Old value of the database field that was edited' },
            'new_value' => { description => 'New value of the database field that was edited' }
        }
    },

};

=head1 METHODS

=head2 (static) C<log_activity($db, $activity_name, $user, $object_id, $reason, $description_hash)>

Log activity.

Parameters:

=over 4

=item * C<$db> - Reference to the database object.

=item * C<$activity_name> - Activity name from the C<%ACTIVITIES> hash, e.g.
C<cm_mine_controversy>.

=item * C<$user> - User that initiated the activity, either: a) user's email,
e.g. C<jdoe@cyber.law.harvard.edu>, or b) system username if the activity was
initiated from the shell and not from the web UI, e.g. C<system:jdoe>.

=item * C<$object_id> - integer ID of an object (e.g. story ID, media ID) that
was modified by the activity (e.g. if the activity was C<story_edit>, this
parameter should be a story ID that was edited). Pass 0 if there's no objects
to refer to.

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
sub log_activity($$$$$$)
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
        my $description_json = encode_activity_description( $activity_name, $description_hash );
        unless ( $description_json )
        {
            die "Unable to encode activity description to JSON: $!";
        }

        # Save
        $db->query(
            <<EOF,
            INSERT INTO activities (name, user, object_id, reason, description_json)
            VALUES (?, ?, ?, ?, ?)
EOF
            $activity_name, $user, $object_id, $reason, $description_json
        );
    };
    if ( $@ )
    {
        # Writing the change failed
        say STDERR "Writing activity failed: $@";
        return 0;
    }

    return 1;
}

=head2 (static) C<log_system_activity($db, $activity_name, $object_id, $description_hash)>

Log system activity (the one that was initiated on the shell and not from the
web UI).

See C<log_activity()> for the description of other parameters of this
subroutine.

Returns 1 if the activity was logged. Returns 0 on error.

=cut
sub log_system_activity($$$$)
{
    my ( $db, $activity_name, $object_id, $description_hash ) = @_;

    my $username = getpwuid( $< ) || 'unknown';

    return log_activity( $db, $activity_name, 'system:' . $username, $object_id, '', $description_hash );
}

=head2 (static) C<log_activities($db, $activity_name, $user, $object_id, $reason, $description_hashes)>

Log multiple activities of the same type and the same object at once.

For example, if you're making multiple changes on the same story, you can use
this helper subroutine.

C<$description_hashes> is an arrayref of hashrefs of miscellaneous parameters
that describe each of the activities, e.g.:

    [
        {
            'field' => 'title',   # Field that was edited
            'old_value' => 'Foo...',    # Old value of the field
            'new_value' => 'Bar!'       # New value of the field
        },
        {
            'field' => 'description',
            'old_value' => 'Loren ipsum dolor sit amet.',
            'new_value' => 'Consectetur adipiscing elit.'
        },
        <...>
    ]

See C<log_activity()> for the description of other parameters of this
subroutine.

Returns 1 if the activities were logged. Returns 0 on error.

=cut
sub log_activities($$$$$$)
{
    my ( $db, $activity_name, $user, $object_id, $reason, $description_hashes ) = @_;

    foreach my $description_hash ( @{ $description_hashes } )
    {
        unless ( log_activity( $db, $activity_name, $user, $object_id, $reason, $description_hash ) )
        {
            return 0;
        }
    }

    return 1;
}

=head1 HELPERS

The helpers described below are mainly used by the web UI that lists the
activities from the database.

=head2 (static) C<encode_activity_description($activity_name, $description_hash)>

Validates and encodes an activity description hash to a string value (JSON in
the current implementation).

Parameters:

=over 4

=item * C<$activity_name> - Activity name from the C<%ACTIVITIES> hash, e.g.
C<cm_mine_controversy>.

=item * C<$description_hash> - hashref of miscellaneous parameters that
describe the activity.

=back

Returns a (JSON-encoded) string activity description.

C<die()>s on error.

=cut
sub encode_activity_description($$)
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
    unless ( @expected_parameters ~~ @actual_parameters )
    {
        die "Expected parameters: " .
          join( ' ', @expected_parameters ) . "\n" . "Actual parameters: " .
          join( ' ', @actual_parameters );
    }

    my $description_json = JSON->new->canonical( 1 )->utf8( 1 )->encode( $description_hash );
    unless ( $description_json )
    {
        die "Unable to encode activity description to JSON: $!";
    }

    return $description_json;
}

=head2 (static) C<decode_activity_description($activity_name, $description_hash)>

Decodes an activity description hash from a string value (JSON in the current
implementation).

Parameters:

=over 4

=item * C<$activity_name> - Activity name from the C<%ACTIVITIES> hash, e.g.
C<cm_mine_controversy>.

=item * C<$description_json> - (JSON-encoded) string activity description.

=back

Returns a decoded activity description (hashref of miscellaneous parameters
that describe the activity).

C<die()>s on error.

=cut
sub decode_activity_description($$)
{
    my ( $activity_name, $description_json ) = @_;

    my $description_hash = JSON->new->canonical( 1 )->utf8( 1 )->decode( $description_json );
    unless ( $description_hash )
    {
        die "Unable to decode activity description from JSON: $!";
    }

    return $description_hash;
}

=head2 (static) C<all_activities()>

Returns a array of all activity names.

=cut
sub all_activities()
{
    return keys( %ACTIVITIES );
}

=head2 (static) C<activity($activity_name)>

Returns an activity description for its name.

=cut
sub activity($)
{
    my $activity_name = shift;
    return $ACTIVITIES{ $activity_name };
}

=head2 (static) C<activities_which_reference_column($column_name)>

Return an array of activity names for which the object ID references a specific
table (e.g. C<controversies.controversies_id>).

=cut
sub activities_which_reference_column($)
{
    my $column_name = shift;

    my @activities;
    foreach my $activity_name ( %ACTIVITIES )
    {
        my $activity = $ACTIVITIES{ $activity_name };
        if ( defined $activity->{ object_id }->{ references } )
        {
            if ( $activity->{ object_id }->{ references } eq $column_name )
            {
                push( @activities, $activity_name );
            }
        }
    }

    return @activities;
}

1;
