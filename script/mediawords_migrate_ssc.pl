#!/usr/bin/env perl

# migrate data in story_sentence_counts table into story_sentences table
#
# We are replacing the story_sentence_counts table with an index on story_sentences( md5( sentence ) ).  But for
# some cases we need to know whether a given sentence is the first duplicate (we keep the first duplicate for each
# sentence each media sources each week, but we throw away the subsequent duplicates).  We do this in a script so that
# we can do it in chunks and not lock up the database.

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my ( $max_ssc_id ) = $db->query( "select max( story_sentence_counts_id ) from story_sentence_counts" )->flat;

    die( "can't find max story_sentence_counts_id" ) unless ( $max_ssc_id );

    my $n = 1000000;
    for ( my $i = 0 ; $i < $max_ssc_id ; $i += $n )
    {
        print STDERR "$i ...\n";
        $db->query( <<SQL, $i, $i + $n );
with ssc as (
    select first_stories_id, first_sentence_number
        from story_sentence_counts
        where story_sentence_counts_id between \$1 and \$2 and
            sentence_count > 1
)
update story_sentences ss set is_dup = true, disable_triggers = true
    from ssc
    where ss.stories_id = ssc.first_stories_id and
        ss.sentence_number = ssc.first_sentence_number
SQL
    }
}

main();
