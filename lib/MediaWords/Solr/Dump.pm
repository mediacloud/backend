package MediaWords::Solr::Dump;

use forks;

# code to dump postgres data for import into solr

use strict;
use warnings;

use Data::Dumper;
use Encode;
use LWP::UserAgent;
use List::Util;
use Readonly;
use Text::CSV_XS;

use MediaWords::DB;

# how many sentences to fetch at a time from the postgres query
Readonly my $FETCH_BLOCK_SIZE => 10000;

# max number of updated media stories to import in one delta import
Readonly my $MAX_MEDIA_STORIES => 100000;

# mark date before generating dump for storing in solr_imports after successful import
my $_import_date;

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

# look for media that have been updated since the last import
# and add all of them to a queue.  add enough stories from that
# queue to the stories_solr_import table that there are up to
# $MAX_MEDIA_STORIES in stories_solr_import for each solr_import
sub _add_media_stories_to_import
{
    my ( $db, $import_date, $num_delta_stories ) = @_;

    # temporarily disabling for more testing -hal
    return;

    $db->query( <<END, $import_date );
insert into solr_import_stories ( stories_id )
    select stories_id
        from stories s
            join media m on ( s.media_id = m.media_id )
            left join media_tags_map mtm on ( m.media_id = mtm.media_id )
            left join media_sets_media_map msmm on ( msmm.media_id = m.media_id )
        where
            ( mtm.db_row_last_updated > \$1 or msmm.db_row_last_updated > \$1 ) and
            s.stories_id not in ( select stories_id from stories_for_solr_import ) and
            s.stories_id not in ( select stories_id from solr_import_stories )
END

    my $max_media_stories = List::Util::max( 0, $MAX_MEDIA_STORIES - $num_delta_stories );
    my $num_media_stories = $db->query( <<END, $max_media_stories )->rows;
insert into stories_for_solr_import ( stories_id ) select stories_id from solr_import_stories limit ?
END

    if ( $num_media_stories > 0 )
    {
        $db->query( <<END );
delete from solr_import_stories where stories_id in ( select stories_id from stories_for_solr_import )
END
    }

    print STDERR "added $num_media_stories media stories to the queue\n";
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
    where ss.db_row_last_updated > \$1
END
        my ( $num_delta_stories ) = $db->query( "select count(*) from stories_for_solr_import" )->flat;
        print STDERR "found $num_delta_stories stories for import ...\n";

        _add_media_stories_to_import( $db, $import_date, $num_delta_stories );

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
        ss.story_sentences_id,
        ss.stories_id || '!' || ss.story_sentences_id solr_id,
        to_char( date_trunc( 'minute', publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_date,
        to_char( date_trunc( 'hour', publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_day,
        ss.sentence_number,
        ss.sentence,
        ss.language
    
    from story_sentences ss
        
    where ( ss.stories_id % $num_proc = $proc - 1 )
        $date_clause
END

    my $fields = [
        qw/stories_id media_id story_sentences_id solr_id publish_date publish_day sentence_number sentence language
          processed_stories_id media_sets_id tags_id_media tags_id_stories tags_id_story_sentences/
    ];

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    $csv->combine( @{ $fields } );

    print FILE $csv->string . "\n";

    my $imported_stories_ids = {};
    my $i                    = 0;
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
            my $story_sentences_id = $row->[ 2 ];

            my $processed_stories_id = $ps_lookup->{ $stories_id };
            next unless ( $processed_stories_id );

            my $media_sets_list   = $media_sets_lookup->{ $media_id }        || '';
            my $media_tags_list   = $media_tags_lookup->{ $media_id }        || '';
            my $stories_tags_list = $stories_tags_lookup->{ $stories_id }    || '';
            my $ss_tags_list      = $ss_tags_lookup->{ $story_sentences_id } || '';

            $csv->combine( @{ $row }, $processed_stories_id, $media_sets_list, $media_tags_list, $stories_tags_list,
                $ss_tags_list );
            print FILE encode( 'utf8', $csv->string . "\n" );

            $imported_stories_ids->{ $stories_id } = 1;
        }

        print STDERR time . " " . ( $i * $FETCH_BLOCK_SIZE ) . "\n";    # unless ( ++$i % 10 );
    }

    $dbh->do( "close csr" );
    $db->commit;

    close( FILE );

    return [ keys( %{ $imported_stories_ids } ) ];
}

# print a csv dump of the postgres data to $file_spec.
# run num_proc jobs in parallel to generate the dump
# if delta is true, only dump the data changed since the last dump
sub print_csv_to_file
{
    my ( $file_spec, $num_proc, $delta ) = @_;

    $num_proc //= 1;

    my $files;

    if ( $num_proc == 1 )
    {
        return _print_csv_to_file_single_job( $file_spec, 1, 1, $delta );
    }
    else
    {
        my $threads = [];

        for my $proc ( 1 .. $num_proc )
        {
            my $file = "$file_spec-$proc";
            push( @{ $files }, $file );

            push( $threads, threads->create( \&_print_csv_to_file_single_job, $file, $num_proc, $proc, $delta ) );
        }

        my $all_stories_ids = [];
        for my $thread ( @{ $threads } )
        {
            my $stories_ids = $thread->join();
            push( $all_stories_ids, $stories_ids );
        }

        return $all_stories_ids;
    }
}

# send a request to MediaWords::Solr::get_solr_url.  return 1
# on success and 0 on error.
sub _solr_request
{
    my ( $url ) = @_;

    # print STDERR "requesting url: $url ...\n";

    my $solr_url = MediaWords::Util::Config::get_config->{ mediawords }->{ solr_url }->[ 0 ];

    if ( $solr_url !~ /^https?\:\/\/localhost/ )
    {
        warn( "import failed for solr url '$solr_url'. Can only import to localhost solr url" );
        return 0;
    }

    my $abs_url = "${ solr_url }${ url }";

    my $ua = LWP::UserAgent->new;
    $ua->timeout( 86400 * 7 );
    my $res = $ua->get( $abs_url );

    if ( $res->is_success )
    {
        # print STDERR $res->content;
        return 1;
    }
    else
    {
        warn( "request failed: " . $res->as_string );
        return 0;
    }

}

# import a single csv dump file into solr
sub _import_csv_single_file
{
    my ( $file, $delta ) = @_;

    my $abs_file = File::Spec->rel2abs( $file );

    print STDERR "importing $abs_file ...\n";

    my $overwrite = $delta ? 'overwrite=true' : 'overwrite=false';

    my $url =
"/update/csv?commit=false&stream.file=$abs_file&stream.contentType=text/plain;charset=utf-8&f.media_sets_id.split=true&f.media_sets_id.separator=;&f.tags_id_media.split=true&f.tags_id_media.separator=;&f.tags_id_stories.split=true&f.tags_id_stories.separator=;&f.tags_id_story_sentences.split=true&f.tags_id_story_sentences.separator=;&$overwrite&skip=field_type,id,solr_import_date";

    return _solr_request( $url );
}

# import csv dump files into solr.  if there are multiple files,
# import up to 4 at a time.
sub import_csv_files
{
    my ( $files, $delta ) = @_;

    my $r;
    if ( @{ $files } == 1 )
    {
        $r = _import_csv_single_file( $files->[ 0 ], $delta );
    }
    else
    {
        my $threads = [];
        for my $file ( @{ $files } )
        {
            push( $threads, threads->create( \&_import_csv_single_file, $file, $delta ) );
        }

        $r = 1;
        map { $r = $r && $_->join } @{ $threads };
    }

    if ( !$r )
    {
        print STDERR "IMPORT FAILED.\n";
        return 0;
    }

    return _solr_request( "/update?stream.body=<commit/>" );
}

# store in memory the current date according to postgres
sub mark_import_date
{
    my ( $db ) = @_;

    $_import_date = $db->query( "select now()" )->flat;
}

# store the date marked by mark_import_date in solr_imports
sub save_import_date
{
    my ( $db, $delta ) = @_;

    die( "import date has not been marked" ) unless ( $_import_date );

    my $full_import = $delta ? 'f' : 't';
    $db->query( "insert into solr_imports( import_date, full_import ) values ( ?, ? )", $_import_date, $full_import );
}

# delete the given stories from solr
sub delete_stories
{
    my ( $stories_ids ) = @_;

    return 1 unless ( $stories_ids && @{ $stories_ids } );

    print STDERR "deleting " . scalar( @{ $stories_ids } ) . " stories ...\n";

    # send requests in chunks so the requests are not too big
    my $chunk_size = 100;
    for ( my $i = 0 ; $i < @{ $stories_ids } ; $i += $chunk_size )
    {
        my $ceil = List::Util::min( scalar( @{ $stories_ids } ), $i + $chunk_size ) - 1;
        my $chunk_ids = [ ( @{ $stories_ids } )[ $i .. $ceil ] ];

        my $chunk_ids_list = join( ' ', @{ $chunk_ids } );
        my $r = _solr_request( "/update?stream.body=<delete><query>+stories_id:(${ chunk_ids_list })</query></delete>" );

        return 0 unless $r;
    }

    return 1;
}

# delete all stories from solr
sub delete_all_sentences
{
    print STDERR "deleting all sentences ...\n";

    return _solr_request( "/update?stream.body=<delete><query>*:*</query></delete>" );
}

# get a temp file name to for a delta dump
sub _get_dump_file
{
    my $data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

    my $dump_dir = "$data_dir/solr_dumps";

    mkdir( $dump_dir ) unless ( -d $dump_dir );

    my ( $fh, $filename ) = File::Temp::tempfile( 'solr-delta.csvXXXX', DIR => $dump_dir );
    close( $fh );

    return $filename;
}

# generate and import dump.  optionally generate delta dump since beginning of last
# full or delta dump.  optionally delete all solr data after generating dump and before
# importing
sub generate_and_import_data
{
    my ( $delta, $delete ) = @_;

    die( "cannot import with delta and delete both true" ) if ( $delta && $delete );

    my $db = MediaWords::DB::connect_to_db;

    my $dump_file = _get_dump_file();

    mark_import_date( $db );

    print STDERR "generating dump ...\n";
    my $stories_ids = print_csv_to_file( $dump_file, 1, $delta ) || die( "dump failed." );

    if ( $delta )
    {
        print STDERR "deleting updated stories ...\n";
        delete_stories( $stories_ids ) || die( "delete stories failed." );
    }
    elsif ( $delete )
    {
        print STDERR "deleting all stories ...\n";
        delete_all_sentences() || die( "delete all sentences failed." );
    }

    print STDERR "importing dump ...\n";
    import_csv_files( [ $dump_file ], $delta ) || die( "import failed." );

    save_import_date( $db, $delta );

    # if we're doing a full import, do a delta to catchup with the data since the start of the import
    if ( !$delta )
    {
        generate_and_import_data( 1 );
    }

    #unlink( $filename );
}

1;
