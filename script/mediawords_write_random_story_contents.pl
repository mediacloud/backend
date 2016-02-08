#!/usr/bin/env perl

# get X random stories from the database and write the content of each to a story_content/<stories_id> file.

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Encode;
use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::DBI::Stories;

sub get_story_content
{
    my ( $db, $story ) = @_;

    my $content_ref;

    eval { $content_ref = MediaWords::DBI::Stories::get_content_for_first_download( $db, $story ) };
    if ( $@ || !$content_ref )
    {
        warn( "error fetching content: $@" );
        return 0;
    }

    return $$content_ref;
}

sub main
{
    my ( $num_stories ) = @ARGV;

    die( "usage: $0 <num stories>" ) unless ( $num_stories );

    my $db = MediaWords::DB::connect_to_db;

    my ( $max_stories_id ) = $db->query( "select max( stories_id ) from stories" )->flat;

    say STDERR "max: $max_stories_id ";

    for ( my $i = 0 ; $i < $num_stories ; $i++ )
    {
        my $random_stories_id = int( rand( $max_stories_id ) );

        my $story = $db->query( <<SQL, )->hash;
select * from stories where stories_id > $random_stories_id order by stories_id limit 1;
SQL

        my $content = get_story_content( $db, $story );

        say STDERR "writing $story->{ stories_id } ...";

        open( FILE, ">story_content/$story->{ stories_id }" )
          || die( "Unable to open file for $story->{ stories_id }: $!" );

        print FILE encode( 'utf8', $content );

        close FILE

    }
}

main();
