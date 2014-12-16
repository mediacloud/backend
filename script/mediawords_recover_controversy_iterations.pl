#!/usr/bin/env perl

#
# regenerate controversy_stories.iteration for every controversy story with an iteration = 1000
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;

sub _get_controversy_stories
{
    my ( $db ) = @_;

    my $cs = $db->query( "select * from controversy_stories where iteration >= 1000 limit 1000" )->hashes;

    return ( @{ $cs } ) ? $cs : undef;
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my ( $n ) = $db->query( "select count(*) from controversy_stories where iteration >= 1000" )->flat;

    my $i = 0;
    while ( my $controversy_stories = _get_controversy_stories( $db ) )
    {
        $db->begin;
        for my $cs ( @{ $controversy_stories } )
        {
            my ( $iteration ) = $db->query( <<END, $cs->{ stories_id } )->flat;
select iteration
    from
        controversy_links cl
        join controversy_stories ls on ( cl.stories_id = ls.stories_id and cl.controversies_id = ls.controversies_id )
    where
        cl.ref_stories_id = ?
    order by iteration asc
    limit 1            
END

            $iteration = 1 if ( !defined( $iteration ) || ( $iteration >= 1000 ) );
            $i++;
            print "$i / $n [$iteration]\n";

            $db->query( <<END, $iteration, $cs->{ controversy_stories_id } );
update controversy_stories set iteration = ? where controversy_stories_id = ?
END

        }
        $db->commit;
    }
}

main();
