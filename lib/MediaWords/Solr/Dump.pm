package MediaWords::Solr::Dump;

# code to postgres data for import into solr

use strict;
use warnings;

use Encode;
use LWP::UserAgent;
use Parallel::ForkManager;
use Readonly;
use Text::CSV_XS;

use MediaWords::DB;

# max number of imports to run at one time -- too many
# parallel imports makes solr flaky
Readonly my $MAX_IMPORT_JOBS => 4;

# how many sentences to fetch at a time from the postgres query
Readonly my $FETCH_BLOCK_SIZE => 10000;

# run a postgres query and generate a table that lookups on the first column by the second column
sub _get_lookup
{
    my ( $db, $query ) = @_;

    my $rows = $db->query( $query )->arrays;

    my $lookup = {};
    for my $row ( @{ $rows } )
    {
        $lookup->{ $row->[ 1 ] } = $row->[ 0 ];
    }

    return $lookup;
}

# print a csv dump of the postgres data to $file_spec.
# run num_proc jobs in parallel to generate the dump
# if delta is true, only dump the data changed since the last dump
sub print_csv_to_file
{
    my ( $file_spec, $num_proc, $delta ) = @_;

    $num_proc //= 1;

    my $files;

    my $db = MediaWords::DB::connect_to_db;
    my ( $now ) = $db->query( "select now()" )->flat;

    if ( $num_proc == 1 )
    {
        _print_csv_to_file_single_job( $file_spec, 1, 1, $delta );
        $files = [ $file_spec ];
    }
    else
    {
        my $pm = new Parallel::ForkManager( $num_proc );

        for my $proc ( 1 .. $num_proc )
        {
            my $file = "$file_spec-$proc";

            push( @{ $files }, $file );

            $pm->start and next;

            _print_csv_to_file_single_job( $file, $num_proc, $proc, $delta );

            $pm->finish;
        }

        $pm->wait_all_children;
    }

    my $full_import = $delta ? 'f' : 't';
    $db->query( "insert into solr_imports( import_date, full_import ) values ( ?, ? )", $now, $full_import );

    return $files;
}

# print a csv dump of the postgres data to $file.
# run as job proc out of num_proc jobs, where each job is printg
# a separate set of data.
# if delta is true, only dump the data changed since the last dump
sub _print_csv_to_file_single_job
{
    my ( $file, $num_proc, $proc, $delta ) = @_;

    open( FILE, ">$file" ) || die( "Unable to open file '$file': $@" );

    my $db = MediaWords::DB::connect_to_db;

    print STDERR "generating lookup data ...\n";

    my $date_clause = '';
    if ( $delta )
    {
        my ( $import_date ) = $db->query( "select import_date from solr_imports order by import_date desc limit 1" )->flat;

        $import_date //= '2000-01-01';

        print STDERR "importing delta from $import_date...\n";

        $db->query( <<END, $import_date );
create temporary table stories_for_solr_import as
    select distinct stories_id
    from story_sentences ss
    where ss.db_row_last_updated > ?
END

        my ( $num_delta_stories ) = $db->query( "select count(*) from stories_for_solr_import" )->flat;
        print STDERR "found $num_delta_stories stories for import ...\n";

        $date_clause = "and stories_id in ( select stories_id from stories_for_solr_import )";
    }

    my $ps_lookup = _get_lookup( $db, <<END );
select processed_stories_id, stories_id from processed_stories where stories_id % $num_proc = $proc - 1 $date_clause
END

    my $media_sets_lookup = _get_lookup( $db, <<END );
select string_agg( media_sets_id::text, ';' ) media_sets_id, media_id from media_sets_media_map group by media_id
END
    my $media_tags_lookup = _get_lookup( $db, <<END );
select string_agg( tags_id::text, ';' ) tag_list, media_id from media_tags_map group by media_id
END
    my $stories_tags_lookup = _get_lookup( $db, <<END );
select string_agg( tags_id::text, ';' ) tag_list, stories_id 
    from stories_tags_map 
    where stories_id % $num_proc = $proc - 1 $date_clause
    group by stories_id
END
    my $ss_tags_lookup = _get_lookup( $db, <<END );
select string_agg( tags_id::text, ';' ) tag_list, story_sentences_id 
    from story_sentences_tags_map 
    group by story_sentences_id
END

    my $dbh = $db->dbh;

    $db->begin;
    $dbh->do( <<END );
declare csr cursor for

    select 
        ss.stories_id, 
        ss.media_id, 
        to_char( publish_date, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_date, 
        ss.story_sentences_id, 
        ss.sentence_number, 
        ss.sentence, 
        ss.language
    
    from story_sentences ss 
        
    where ( ss.stories_id % $num_proc = $proc - 1 )
        $date_clause
END

    my $fields = [
        qw/stories_id media_id publish_date story_sentences_id sentence_number sentence language
          processed_stories_id media_sets_id tags_id_media tags_id_stories tags_id_story_sentences/
    ];

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    $csv->combine( @{ $fields } );

    print FILE $csv->string . "\n";

    my $i = 0;
    while ( 1 )
    {
        my $sth = $dbh->prepare( "fetch $FETCH_BLOCK_SIZE from csr" );

        $sth->execute;

        last if 0 == $sth->rows;

        # use fetchrow_arrayref to optimize fetching and lookup speed below -- perl
        # cpu is a significant bottleneck for this script
        while ( my $row = $sth->fetchrow_arrayref )
        {
            my $stories_id         = $row->[ 0 ];
            my $media_id           = $row->[ 1 ];
            my $story_sentences_id = $row->[ 3 ];

            my $processed_stories_id = $ps_lookup->{ $stories_id };
            next unless ( $processed_stories_id );

            my $media_sets_list   = $media_sets_lookup->{ $media_id }        || '';
            my $media_tags_list   = $media_tags_lookup->{ $media_id }        || '';
            my $stories_tags_list = $stories_tags_lookup->{ $stories_id }    || '';
            my $ss_tags_list      = $ss_tags_lookup->{ $story_sentences_id } || '';

            $csv->combine( @{ $row }, $processed_stories_id, $media_sets_list, $media_tags_list, $stories_tags_list,
                $ss_tags_list );
            print FILE encode( 'utf8', $csv->string . "\n" );
        }
        print STDERR time . " " . ( $i * $FETCH_BLOCK_SIZE ) . "\n" if ( $i++ );
    }

    $dbh->do( "close csr" );
    $db->commit;

    close( FILE );
}

# import a single csv dump file into solr
sub _import_csv_single_file
{
    my ( $file, $delta ) = @_;

    my $abs_file = File::Spec->rel2abs( $file );

    print STDERR "importing $abs_file ...\n";

    my $overwrite = $delta ? 'overwrite=true' : 'overwrite=false';

    my $url =
"http://localhost:7983/solr/update/csv?commit=false&stream.file=$abs_file&stream.contentType=text/plain;charset=utf-8&f.media_sets_id.split=true&f.media_sets_id.separator=;&f.tags_id_media.split=true&f.tags_id_media.separator=;&f.tags_id_stories.split=true&f.tags_id_stories.separator=;&f.tags_id_story_sentences.split=true&f.tags_id_story_sentences.separator=;&$overwrite&skip=field_type,id,solr_import_date";

    print STDERR "$url\n";

    my $ua = LWP::UserAgent->new;
    $ua->timeout( 86400 * 7 );
    my $res = $ua->get( $url );

    if ( $res->is_success )
    {
        print STDERR $res->content;
    }
    else
    {
        die( "import request failed: " . $res->as_string );
    }
}

# import csv dump files into solr.  if there are multiple files,
# import up to 4 at a time.
sub import_csv_files
{
    my ( $files, $delta ) = @_;

    if ( @{ $files } == 1 )
    {
        _import_csv_single_file( $files->[ 0 ], $delta );
    }
    else
    {
        my $pm = new Parallel::ForkManager( $MAX_IMPORT_JOBS );

        for my $file ( @{ $files } )
        {
            $pm->start and next;

            _import_csv_single_file( $file, $delta );

            $pm->finish;
        }

        $pm->wait_all_children;
    }

    print STDERR "comitting ..\n";
    my $ua = LWP::UserAgent->new;
    $ua->timeout( 86400 * 7 );
    my $res = $ua->get( 'http://localhost:7983/solr/update?stream.body=<commit/>' );

    if ( $res->is_success )
    {
        print STDERR $res->content;
    }
    else
    {
        die( "commit request failed: " . $res->as_string );
    }

}

1;
