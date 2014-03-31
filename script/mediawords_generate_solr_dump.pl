#!/usr/bin/env perl

# generate csv dump of story_sentences and related tables for importing into solr

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Encode;
use Text::CSV_XS;

use MediaWords::DB;

sub get_lookup
{
    my ( $db, $query ) = @_;

    print STDERR "generating lookup '$query'\n";

    my $rows = $db->query( $query )->arrays;

    my $lookup = {};
    for my $row ( @{ $rows } )
    {
        $lookup->{ $row->[ 1 ] } = $row->[ 0 ];
    }

    return $lookup;
}

sub main
{
    my ( $num_proc, $proc ) = @ARGV;

    $num_proc ||= 1;
    $proc     ||= 1;

    my $db = MediaWords::DB::connect_to_db;

    my $ps_lookup = get_lookup( $db, <<END );
select processed_stories_id, stories_id from processed_stories where stories_id % $num_proc = $proc - 1
END

    my $media_sets_lookup = get_lookup( $db, <<END );
select string_agg( media_sets_id::text, ';' ) media_sets_id, media_id from media_sets_media_map group by media_id
END
    my $media_tags_lookup = get_lookup( $db, <<END );
select string_agg( tags_id::text, ';' ) tag_list, media_id from media_tags_map group by media_id
END
    my $stories_tags_lookup = get_lookup( $db, <<END );
select string_agg( tags_id::text, ';' ) tag_list, stories_id from stories_tags_map where stories_id % $num_proc = $proc - 1 group by stories_id
END
    my $ss_tags_lookup = get_lookup( $db, <<END );
select string_agg( tags_id::text, ';' ) tag_list, story_sentences_id from story_sentences_tags_map group by story_sentences_id
END

    my $dbh = $db->dbh;

    print STDERR "starting ss query\n";

    $db->begin;
    $dbh->do( <<END );
declare csr cursor for

    select 
        ss.story_sentences_id || '_ss' as id, 
        'ss' as field_type, 
        to_char( now(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as solr_import_date, 
        ss.stories_id, 
        ss.media_id, 
        to_char( publish_date, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_date, 
        ss.story_sentences_id, 
        ss.sentence_number, 
        ss.sentence, 
        ss.language
    
    from story_sentences ss 
        
    where ss.stories_id % $num_proc = $proc - 1
END

    my $fields = [
        qw/id field_type solr_import_date stories_id media_id
          publish_date story_sentences_id sentence_number sentence language
          processed_stories_id media_sets_id tags_id_media tags_id_stories tags_id_story_sentences/
    ];

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    $csv->combine( @{ $fields } );

    print $csv->string . "\n";

    my $i = 0;
    while ( 1 )
    {
        print STDERR time . " " . ( $i++ * 1000 ) . "\n";
        my $sth = $dbh->prepare( "fetch 1000 from csr" );

        $sth->execute;

        last if 0 == $sth->rows;

        # use fetchrow_arrayref to optimize fetching and lookup speed below -- perl
        # cpu is a significant bottleneck for this script
        while ( my $row = $sth->fetchrow_arrayref )
        {
            my $stories_id         = $row->[ 3 ];
            my $media_id           = $row->[ 4 ];
            my $story_sentences_id = $row->[ 6 ];

            my $processed_stories_id = $ps_lookup->{ $stories_id };
            next unless ( $processed_stories_id );

            my $media_sets_list   = $media_sets_lookup->{ $media_id }        || '';
            my $media_tags_list   = $media_tags_lookup->{ $media_id }        || '';
            my $stories_tags_list = $stories_tags_lookup->{ $stories_id }    || '';
            my $ss_tags_list      = $ss_tags_lookup->{ $story_sentences_id } || '';

            $csv->combine( @{ $row }, $processed_stories_id, $media_sets_list, $media_tags_list, $stories_tags_list,
                $ss_tags_list );
            print encode( 'utf8', $csv->string . "\n" );
        }
    }

    $dbh->do( "close csr" );
    $db->commit;
}

main();
