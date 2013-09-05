#!/usr/bin/env perl

# rerun MediaWords::CM::Mine::story_matches_controversy_pattern on all stories within a controversy
# and delete those that do not match the controversy

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::CM::Mine;
use MediaWords::DB;
use MediaWords::DBI::Controversies;

sub main
{
    my ( $controversy_opt );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    Getopt::Long::GetOptions( "controversy=s" => \$controversy_opt ) || return;

    die( "Usage: $0 --controversy < id >" ) unless ( $controversy_opt );

    my $db = MediaWords::DB::connect_to_db;

    my $controversies = MediaWords::DBI::Controversies::require_controversies_by_opt( $db, $controversy_opt );

    for my $controversy ( @{ $controversies } )
    {
        my $stories = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select s.* from cd.live_stories s where controversies_id = ? order by stories_id desc limit 1000
END
        for my $story ( @{ $stories } )
        {
            print STDERR "rematch story: $story->{ stories_id } - $story->{ title } [ $story->{ url } ]\n";
            if ( !MediaWords::CM::Mine::story_matches_controversy_pattern( $db, $controversy, $story ) )
            {
                print STDERR "REMOVE\n";

                #                 $db->query( <<END, $story->{ stories_id }, $controversy->{ controversies_id } );
                # delete from controversy_stories where stories_id = ? and controversies_id = ?
                # END
            }
        }
    }

}

main();
