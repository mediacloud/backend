#!/usr/bin/env perl

# manage the story_sentence_dups index so that it is between 30 and 60 days old.
#
# story_sentence_dups should be a partial index on story_sentences that looks like:
#
# create index story_sentence_dups on story_sentences ( md5( sentence ) )
#        where week_start_date( publish_date::date ) > '2016-01-07'
#
# The clause at the end should always refer to a date at least 30 days in the past and preferably not more than 60
# days in the past.  The goal is to maintain this index only for the last month or two of data, since it is an
# expensive index and 99% of it use is to detect dups within the last month.
#
# To avoid using a big chunk of processing time at once to create a new month old index, instead we only create a
# new index for data starting tomorrow.

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::DB;
use MediaWords::Util::SQL;

# return hash with the results of the query of pg_indexes for the given index, plus
# the date part of the partial index clause, assuming that the index definition looks like:
# create $index_name on story_sentences ( md5( sentence ) ) where week_start_date( publish_date::date ) > $date
sub get_index_info
{
    my ( $db, $index_name ) = @_;

    my $index = $db->query( <<SQL, $index_name )->hash;
select *
    from pg_indexes
    where tablename = 'story_sentences' and
        indexname = ?
SQL

    return undef unless ( $index );

    die( "Can't find date in '$index_name' index" ) unless ( $index->{ indexdef } =~ /(\d\d\d\d-\d\d-\d\d)/ );

    $index->{ date }       = $1;
    $index->{ epoch_date } = MediaWords::Util::SQL::get_epoch_from_sql_date( $index->{ date } );

    return $index;
}

# create a new story_sentences_dup_new index
sub create_new_index
{
    my ( $db ) = @_;

    my $start_date = MediaWords::Util::SQL::get_sql_date_from_epoch( time() );

    $db->query( <<SQL );
create index concurrently story_sentences_dup_new on story_sentences( md5( sentence ) )
    where week_start_date( publish_date::date ) > '$start_date'::date
SQL
}

# drop the old story_sentences_dup index and rename story_sentences_dup_new to story_sentences_dup
sub switch_indexes
{
    my ( $db ) = @_;

    $db->begin;

    $db->query( "drop index story_sentences_dup" );
    $db->query( "alter index story_sentences_dup_new rename to story_sentences_dup" );

    $db->commit;
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $current_index = get_index_info( $db, 'story_sentences_dup' );
    my $new_index     = get_index_info( $db, 'story_sentences_dup_new' );

    die( "story_sentences_dup index does not exist" ) if ( !$current_index );

    if ( !$new_index )
    {
        create_new_index( $db );
    }
    elsif ( $new_index->{ epoch_date } < ( time() - ( 30 * 86400 ) ) )
    {
        switch_indexes( $db );
    }
}

main();
