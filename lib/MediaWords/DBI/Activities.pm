package MediaWords::DBI::Activities;
#
# Package to log various activities (story edits, media edits, etc.)
#

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use JSON;

# Available activities
# (FIXME make it possible to check the activity on the compile time)
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
                references  => 'story.stories_id'
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

# Write many activity log entries
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

# Write system activity log entry (doesn't have an user's email nor reason)
sub log_system_activity($$$$)
{
    my ( $db, $activity_name, $object_id, $description_hash ) = @_;

    my $username = getpwuid( $< ) || 'unknown';

    return log_activity( $db, $activity_name, 'system:' . $username, $object_id, '', $description_hash );
}

# Write activity log entry
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

# Encode activity description's hash (to JSON)
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

# Decode activity description's hash (from JSON)
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

# Return a list of all activities
sub all_activities()
{
    return keys( %ACTIVITIES );
}

# Return an activity for key
sub activity($)
{
    my $activity_name = shift;
    return $ACTIVITIES{ $activity_name };
}

# Return a list of activities of which the object ID references a specific
# table (e.g. 'controversies.controversies_id')
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
