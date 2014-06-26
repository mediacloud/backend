#!/usr/bin/env perl

# generate csv of all sentences in a controversy
# usage: mediawords_dump_controversy_sentences.pl --controversy < id >

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::DB;

sub main
{
    my ( $controversies_id, $dedup_stories, $import_only, $cache_broken_downloads );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Getopt::Long::GetOptions( "controversy=s" => \$controversies_id, ) || return;

    die( "usage: $0 --controversy < controversies_id >" ) unless ( $controversies_id );

    my $db = MediaWords::DB::connect_to_db;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id )
      || die( "Unable to find controversy '$controversies_id'" );

    $db->dbh->do( <<END );
copy (
    select s.publish_date, s.media_id, s.stories_id, ss.sentence_number, ss.sentence
        from stories s
            join controversy_stories cs on ( s.stories_id = cs.stories_id )
            join controversies c on ( c.controversies_id = cs.controversies_id )
            join query_story_searches qss on ( c.query_story_searches_id = qss.query_story_searches_id )
            join story_sentences ss on ( s.stories_id = ss.stories_id )
            join story_sentence_counts ssc on 
                ( ss.stories_id = ssc.first_stories_id and ss.sentence_number = ssc.first_sentence_number )
        where
            cs.controversies_id = $controversy->{ controversies_id } and
            ssc.sentence_count < 2 and
            ss.sentence ~* qss.pattern
        order by ss.stories_id, ss.sentence_number
    ) to STDOUT
    with csv header
END

    my $buffer;
    while ( $db->dbh->pg_getcopydata( $buffer ) > -1 )
    {
        print $buffer;
    }
}

main();
