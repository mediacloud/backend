#!/usr/bin/env perl

# set the primary language field for any media for which it is not set

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Media;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $tag_set = MediaWords::DBI::Media::get_primary_language_tag_set( $db );

    my $media = $db->query( <<SQL, $tag_set->{ tag_sets_id } )->hashes;
select m.*
    from media m
        left join (
            media_tags_map mtm
            join tags t on ( t.tags_id = mtm.tags_id and t.tag_sets_id = \$1 )
        ) using ( media_id )
    where
        mtm.tags_id is null
SQL

    map { MediaWords::DBI::Media::set_primary_language( $db, $_ ) } @{ $media };

}

main();
