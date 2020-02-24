package MediaWords::TM::Snapshot::ExtraFields;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

# attributes to include in gexf snapshot
our $MEDIA_STATIC_GEXF_ATTRIBUTE_TYPES = {
    url                    => 'string',
    inlink_count           => 'integer',
    story_count            => 'integer',
    view_medium            => 'string',
    media_type             => 'string',
    facebook_share_count   => 'integer',
    post_count             => 'integer',
};


sub _add_partisan_code_to_snapshot_media
{
    my ( $db, $timespan, $media ) = @_;

    my $label = 'partisan_code';

    my $partisan_tags = $db->query( <<END )->hashes;
select dmtm.*, dt.tag
    from snapshot_media_tags_map dmtm
        join tags dt on ( dmtm.tags_id = dt.tags_id )
        join tag_sets dts on ( dts.tag_sets_id = dt.tag_sets_id )
    where
        dts.name = 'collection' and
        dt.tag like 'partisan_2012_%'
END

    my $map = {};
    map { $map->{ $_->{ media_id } } = $_->{ tag } } @{ $partisan_tags };

    map { $_->{ $label } = $map->{ $_->{ media_id } } || 'null' } @{ $media };

    return $label;
}

sub _add_partisan_retweet_to_snapshot_media
{
    my ( $db, $timespan, $media ) = @_;

    my $label = 'partisan_retweet';

    my $partisan_tags = $db->query( <<END )->hashes;
select dmtm.*, dt.tag
    from snapshot_media_tags_map dmtm
        join tags dt on ( dmtm.tags_id = dt.tags_id )
        join tag_sets dts on ( dts.tag_sets_id = dt.tag_sets_id )
    where
        dts.name = 'retweet_partisanship_2016_count_10'
END

    my $map = {};
    map { $map->{ $_->{ media_id } } = $_->{ tag } } @{ $partisan_tags };

    map { $_->{ $label } = $map->{ $_->{ media_id } } || 'null' } @{ $media };

    return $label;
}

sub _add_fake_news_to_snapshot_media
{
    my ( $db, $timespan, $media ) = @_;

    my $label = 'fake_news';

    my $tags = $db->query( <<END )->hashes;
select dmtm.*, dt.tag
    from snapshot_media_tags_map dmtm
        join tags dt on ( dmtm.tags_id = dt.tags_id )
        join tag_sets dts on ( dts.tag_sets_id = dt.tag_sets_id )
    where
        dts.name = 'collection' and
        dt.tag = 'fake_news_20170112'
END

    my $map = {};
    map { $map->{ $_->{ media_id } } = $_->{ tag } ? 1 : 0 } @{ $tags };

    map { $_->{ $label } = $map->{ $_->{ media_id } } || 0 } @{ $media };

    return $label;
}

# add tags, codes, partisanship and other extra data to all snapshot media for the purpose
# of making a gexf or csv snapshot.  return the list of extra fields added.
sub add_extra_fields_to_snapshot_media
{
    my ( $db, $timespan, $media ) = @_;

    my $partisan_field = _add_partisan_code_to_snapshot_media( $db, $timespan, $media );
    my $partisan_retweet_field = _add_partisan_retweet_to_snapshot_media( $db, $timespan, $media );
    my $fake_news_field = _add_fake_news_to_snapshot_media( $db, $timespan, $media );

    my $all_fields = [ $partisan_field, $partisan_retweet_field, $fake_news_field ];

    map { $MEDIA_STATIC_GEXF_ATTRIBUTE_TYPES->{ $_ } = 'string'; } @{ $all_fields };

    return $all_fields;
}

1;
