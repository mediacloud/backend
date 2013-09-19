package MediaWords::DBI::Activities;
#
# Package to log various activities (story edits, media edits, etc.)
#

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;

# Available activities
our $ACTIVITIES = {

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

1;
