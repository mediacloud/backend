package MediaWords::Solr::Dump;

use forks;

# code to dump postgres data for import into solr

use strict;
use warnings;

use Data::Dumper;
use Encode;
use FileHandle;
use LWP::UserAgent;
use List::MoreUtils;
use List::Util;
use Readonly;
use Text::CSV_XS;
use URI;

use MediaWords::DB;

use MediaWords::Solr;

# how many sentences to fetch at a time from the postgres query
Readonly my $FETCH_BLOCK_SIZE => 10_000;

# max number of updated queued stories to import in one delta import
Readonly my $MAX_QUEUED_STORIES => 100_000;

# mark date before generating dump for storing in solr_imports after successful import
my $_import_date;

# run a postgres query and generate a table that lookups on the first column by the second column.
# assign that lookup to $data_lookup->{ $name }.
sub _set_lookup
{
    my ( $db, $data_lookup, $name, $query ) = @_;

    my $sth = $db->query( $query );

    my $lookup = {};
    while ( my $row = $sth->array )
    {
        $lookup->{ $row->[ 1 ] } = $row->[ 0 ];
    }

    $data_lookup->{ $name } = $lookup;
}

# add enough stories from the solr_import_extra_stories
# queue to the stories_solr_import table that there are up to
# $MAX_QUEUED_STORIES in stories_solr_import for each solr_import
sub _add_extra_stories_to_import
{
    my ( $db, $import_date, $num_delta_stories ) = @_;

    my $max_queued_stories = List::Util::max( 0, $MAX_QUEUED_STORIES - $num_delta_stories );
    my $num_queued_stories = $db->query(
        <<SQL,
        INSERT INTO delta_import_stories (stories_id)
            SELECT stories_id
            FROM solr_import_extra_stories
            LIMIT ?
SQL
        $max_queued_stories
    )->rows;

    if ( $num_queued_stories > 0 )
    {
        my ( $total_queued_stories ) = $db->query( 'SELECT COUNT(*) FROM solr_import_extra_stories' )->flat;

        print STDERR "added $num_queued_stories / $total_queued_stories queued stories to the import\n";
    }

}

# setup 'csr' cursor in postgres as the query to import the story_sentences
sub _declare_sentences_cursor
{
    my ( $db, $delta, $num_proc, $proc ) = @_;

    my $date_clause = $delta ? 'and ss.stories_id in ( select stories_id from delta_import_stories )' : '';

    $db->dbh->do( <<END );
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
        null title,
        ss.language,
        bitly_clicks_total.click_count as bitly_click_count

    from story_sentences ss
        left join bitly_clicks_total
            on ss.stories_id = bitly_clicks_total.stories_id

    where ( ss.stories_id % $num_proc = $proc - 1 )
        $date_clause
END

}

# setup 'csr' cursor in postgres as the query to import the story titles
sub _declare_titles_cursor
{
    my ( $db, $delta, $num_proc, $proc ) = @_;

    my $date_clause = $delta ? 'and s.stories_id in ( select stories_id from delta_import_stories )' : '';

    $db->dbh->do( <<END );
declare csr cursor for

    select
        s.stories_id,
        s.media_id,
        0 story_sentences_id,
        s.stories_id || '!' || 0 solr_id,
        to_char( date_trunc( 'minute', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_date,
        to_char( date_trunc( 'hour', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_day,
        0,
        null sentence,
        s.title,
        s.language,
        bitly_clicks_total.click_count as bitly_click_count

    from stories s
        left join bitly_clicks_total
            on s.stories_id = bitly_clicks_total.stories_id

    where ( s.stories_id % $num_proc = $proc - 1 )
        $date_clause
END

}

# incrementally read the results from the 'csr' postgres cursor and print out the resulting
# sorl dump csv to the file
sub _print_csv_to_file_from_csr
{
    my ( $db, $fh, $data_lookup, $print_header ) = @_;

    my $fields = [
        qw/stories_id media_id story_sentences_id solr_id publish_date publish_day sentence_number sentence title language
          bitly_click_count processed_stories_id media_sets_id tags_id_media tags_id_stories tags_id_story_sentences/
    ];

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    if ( $print_header )
    {
        $csv->combine( @{ $fields } );
        $fh->print( $csv->string . "\n" );
    }

    my $imported_stories_ids = {};
    my $i                    = 0;
    while ( 1 )
    {
        my $sth = $db->dbh->prepare( "fetch $FETCH_BLOCK_SIZE from csr" );

        $sth->execute;

        last if 0 == $sth->rows;

        # use fetchrow_arrayref to optimize fetching and lookup speed below -- perl
        # cpu is a significant bottleneck for this script
        while ( my $row = $sth->fetchrow_arrayref )
        {
            my $stories_id         = $row->[ 0 ];
            my $media_id           = $row->[ 1 ];
            my $story_sentences_id = $row->[ 2 ];

            my $processed_stories_id = $data_lookup->{ ps }->{ $stories_id };
            next unless ( $processed_stories_id );

            my $media_sets_list   = $data_lookup->{ media_sets }->{ $media_id }        || '';
            my $media_tags_list   = $data_lookup->{ media_tags }->{ $media_id }        || '';
            my $stories_tags_list = $data_lookup->{ stories_tags }->{ $stories_id }    || '';
            my $ss_tags_list      = $data_lookup->{ ss_tags }->{ $story_sentences_id } || '';

            $csv->combine( @{ $row }, $processed_stories_id, $media_sets_list, $media_tags_list, $stories_tags_list,
                $ss_tags_list );
            $fh->print( encode( 'utf8', $csv->string . "\n" ) );

            $imported_stories_ids->{ $stories_id } = 1;
        }

        print STDERR time . " " . ( ++$i * $FETCH_BLOCK_SIZE ) . "\n";    # unless ( ++$i % 10 );
    }

    $db->dbh->do( "close csr" );

    return [ keys %{ $imported_stories_ids } ];
}

# get the date clause that restricts the import of all subsequent queries to just the
# delta stories
sub _create_delta_import_stories
{
    my $db = shift;

    my ( $import_date ) = $db->query( "select import_date from solr_imports order by import_date desc limit 1" )->flat;

    $import_date //= '2000-01-01';

    print STDERR "importing delta from $import_date...\n";

    $db->query( <<END, $import_date );
create temporary table delta_import_stories as
select distinct stories_id
from story_sentences ss
where ss.db_row_last_updated > \$1
END
    my ( $num_delta_stories ) = $db->query( "select count(*) from delta_import_stories" )->flat;
    print STDERR "found $num_delta_stories stories for import ...\n";

    _add_extra_stories_to_import( $db, $import_date, $num_delta_stories );
}

# get the $data_lookup hash that has lookup tables for values to include
# for each of the processed_stories, media_sets, media_tags, stories_tags,
# and ss_tags fields for export to solr.
#
# This is basically just a manual
# client side join that we do in perl because we can get postgres to stream
# results much more quickly if we don't ask it to do this giant join on the
# server side.
sub _get_data_lookup
{
    my ( $db, $num_proc, $proc, $delta ) = @_;

    my $data_lookup = {};

    my $date_clause = $delta ? 'and stories_id in ( select stories_id from delta_import_stories )' : '';

    _set_lookup( $db, $data_lookup, 'ps', <<END );
select processed_stories_id, stories_id from processed_stories where stories_id % $num_proc = $proc - 1 $date_clause
END

    _set_lookup( $db, $data_lookup, 'media_sets', <<END );
select string_agg( media_sets_id::text, ';' ) media_sets_id, media_id from media_sets_media_map group by media_id
END
    _set_lookup( $db, $data_lookup, 'media_tags', <<END );
select string_agg( tags_id::text, ';' ) tag_list, media_id from media_tags_map group by media_id
END
    _set_lookup( $db, $data_lookup, 'stories_tags', <<END );
select string_agg( tags_id::text, ';' ) tag_list, stories_id
    from stories_tags_map
    where stories_id % $num_proc = $proc - 1 $date_clause
    group by stories_id
END
    _set_lookup( $db, $data_lookup, 'ss_tags', <<END );
select string_agg( tags_id::text, ';' ) tag_list, story_sentences_id
    from story_sentences_tags_map
    group by story_sentences_id
END

    return $data_lookup;
}

# print a csv dump of the postgres data to $file.
# run as job proc out of num_proc jobs, where each job is printg
# a separate set of data.
# if delta is true, only dump the data changed since the last dump
sub _print_csv_to_file_single_job
{
    my ( $db, $file, $num_proc, $proc, $delta ) = @_;

    # recreate db for forked processes
    $db ||= MediaWords::DB::connect_to_db;

    my $fh = FileHandle->new( ">$file" ) || die( "Unable to open file '$file': $@" );

    if ( $delta )
    {
        _create_delta_import_stories( $db );
    }

    my $data_lookup = _get_data_lookup( $db, $num_proc, $proc, $delta );

    $db->begin;

    print STDERR "exporting sentences ...\n";
    _declare_sentences_cursor( $db, $delta, $num_proc, $proc );
    my $sentence_stories_ids = _print_csv_to_file_from_csr( $db, $fh, $data_lookup, 1 );

    print STDERR "exporting titles ...\n";
    _declare_titles_cursor( $db, $delta, $num_proc, $proc );
    my $title_stories_ids = _print_csv_to_file_from_csr( $db, $fh, $data_lookup, 0 );

    $db->commit;

    return [ List::MoreUtils::uniq( @{ $sentence_stories_ids }, @{ $title_stories_ids } ) ];
}

# print a csv dump of the postgres data to $file_spec.
# run num_proc jobs in parallel to generate the dump.
# assume that the script is running on num_machines different machines.
# if delta is true, only dump the data changed since the last dump.
sub print_csv_to_file
{
    my ( $db, $file_spec, $num_proc, $delta, $min_proc, $max_proc ) = @_;

    $num_proc //= 1;
    $min_proc //= 1;
    $max_proc //= $num_proc;

    my $files;

    if ( $num_proc == 1 )
    {
        return _print_csv_to_file_single_job( $db, $file_spec, 1, 1, $delta );
    }
    else
    {
        my $threads = [];

        for my $proc ( $min_proc .. $max_proc )
        {
            my $file = "$file_spec-$proc";
            push( @{ $files }, $file );

            push( @{ $threads },
                threads->create( \&_print_csv_to_file_single_job, undef, $file, $num_proc, $proc, $delta ) );
        }

        my $all_stories_ids = [];
        for my $thread ( @{ $threads } )
        {
            my $stories_ids = $thread->join();
            push( @{ $all_stories_ids }, $stories_ids );
        }

        return $all_stories_ids;
    }
}

# send a request to MediaWords::Solr::get_solr_url.  return 1
# on success and 0 on error.  if $staging is true, use the staging
# collection; otherwise use the live collection.
sub _solr_request($$$)
{
    my ( $path, $params, $staging ) = @_;

    # print STDERR "requesting url: $url ...\n";

    my $solr_url = MediaWords::Util::Config::get_config->{ mediawords }->{ solr_url }->[ 0 ];

    if ( $solr_url !~ /^https?\:\/\/localhost/ )
    {
        warn( "import failed for solr url '$solr_url'. Can only import to localhost solr url" );
        return 0;
    }

    my $db = MediaWords::DB::connect_to_db;

    my $collection =
      $staging ? MediaWords::Solr::get_staging_collection( $db ) : MediaWords::Solr::get_live_collection( $db );

    my $abs_uri = URI->new( "$solr_url/$collection/$path" );
    $abs_uri->query_form( $params );
    my $abs_url = $abs_uri->as_string;

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
    my ( $file, $delta, $staging ) = @_;

    my $abs_file = File::Spec->rel2abs( $file );

    print STDERR "importing $abs_file ...\n";

    my $url_params = {
        'commit'                              => 'false',
        'stream.file'                         => $abs_file,
        'stream.contentType'                  => 'text/plain',
        'charset'                             => 'utf-8',
        'f.media_sets_id.split'               => 'true',
        'f.media_sets_id.separator'           => ';',
        'f.tags_id_media.split'               => 'true',
        'f.tags_id_media.separator'           => ';',
        'f.tags_id_stories.split'             => 'true',
        'f.tags_id_stories.separator'         => ';',
        'f.tags_id_story_sentences.split'     => 'true',
        'f.tags_id_story_sentences.separator' => ';',
        'overwrite'                           => ( $delta ? 'true' : 'false' ),
        'skip'                                => 'field_type,id,solr_import_date',
    };

    return _solr_request( 'update/csv', $url_params, $staging );
}

# import csv dump files into solr.  if there are multiple files,
# import up to 4 at a time.  If $staging is true, import into the
# staging collection.
sub import_csv_files
{
    my ( $files, $delta, $staging ) = @_;

    my $r;
    if ( scalar @{ $files } == 1 )
    {
        $r = _import_csv_single_file( $files->[ 0 ], $delta, $staging );
    }
    else
    {
        my $threads = [];
        for my $file ( @{ $files } )
        {
            push( @{ $threads }, threads->create( \&_import_csv_single_file, $file, $delta, $staging ) );
        }

        $r = 1;
        map { $r = $r && $_->join } @{ $threads };
    }

    if ( !$r )
    {
        print STDERR "IMPORT FAILED.\n";
        return 0;
    }

    return _solr_request( 'update', { 'stream.body' => '<commit/>' }, $staging );
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
    my ( $db, $delta, $stories_ids ) = @_;

    die( "import date has not been marked" ) unless ( $_import_date );

    my $full_import = $delta ? 'f' : 't';
    $db->query( <<SQL, $_import_date, $full_import, scalar( @{ $stories_ids } ) );
insert into solr_imports( import_date, full_import, num_stories ) values ( ?, ?, ? )
SQL

}

# delete the given stories from solr
sub delete_stories
{
    my ( $stories_ids, $staging ) = @_;

    return 1 unless ( $stories_ids && scalar @{ $stories_ids } );

    print STDERR "deleting " . scalar( @{ $stories_ids } ) . " stories ...\n";

    # send requests in chunks so the requests are not too big
    my $chunk_size = 100;
    for ( my $i = 0 ; $i < scalar @{ $stories_ids } ; $i += $chunk_size )
    {
        my $ceil = List::Util::min( scalar( @{ $stories_ids } ), $i + $chunk_size ) - 1;
        my $chunk_ids = [ ( @{ $stories_ids } )[ $i .. $ceil ] ];

        my $chunk_ids_list = join( ' ', @{ $chunk_ids } );

        my $url_params = { 'stream.body' => "<delete><query>+stories_id:(${ chunk_ids_list })</query></delete>", };
        my $r = _solr_request( 'update', $url_params, $staging );

        return 0 unless $r;
    }

    return 1;
}

# delete all stories from solr
sub delete_all_sentences
{
    my ( $staging ) = @_;

    print STDERR "deleting all sentences ...\n";

    my $url_params = { 'stream.body' => '<delete><query>*:*</query></delete>', };
    return _solr_request( 'update', $url_params, $staging );
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

# delete stories that have just been imported from the media import queue
sub delete_stories_from_import_queue
{
    my ( $db, $delta ) = @_;

    if ( $delta )
    {
        $db->query(
            <<SQL
            DELETE FROM solr_import_extra_stories
            WHERE stories_id IN (
                SELECT stories_id
                FROM delta_import_stories
            )
SQL
        );
    }
    else
    {
        # if we just completed a full import, drop the whole current stories queue
        $db->query( 'TRUNCATE TABLE solr_import_extra_stories' );
    }
}

sub maybe_production_solr
{
    my ( $db ) = @_;

    my $num_sentences = MediaWords::Solr::get_num_found( $db, { q => '*:*', rows => 0 } );

    die( "Unable to query solr for number of sentences" ) unless ( defined( $num_sentences ) );

    return ( $num_sentences > 100_000_000 );
}

# generate and import dump.  optionally generate delta dump since beginning of last
# full or delta dump.  optionally delete all solr data after generating dump and before
# importing
sub generate_and_import_data
{
    my ( $delta, $delete, $staging ) = @_;

    die( "cannot import with delta and delete both true" ) if ( $delta && $delete );

    my $db = MediaWords::DB::connect_to_db;

    die( "refusing to delete maybe production solr" ) if ( $delete && maybe_production_solr( $db ) );

    my $dump_file = _get_dump_file();

    mark_import_date( $db );

    print STDERR "generating dump ...\n";
    my $stories_ids = print_csv_to_file( $db, $dump_file, 1, $delta ) || die( "dump failed." );

    if ( $delta )
    {
        print STDERR "deleting updated stories ...\n";
        delete_stories( $stories_ids, $staging ) || die( "delete stories failed." );
    }
    elsif ( $delete )
    {
        print STDERR "deleting all stories ...\n";
        delete_all_sentences( $staging ) || die( "delete all sentences failed." );
    }

    print STDERR "importing dump ...\n";
    import_csv_files( [ $dump_file ], $delta, $staging ) || die( "import failed." );

    save_import_date( $db, $delta, $stories_ids );
    delete_stories_from_import_queue( $db, $delta );

    # if we're doing a full import, do a delta to catchup with the data since the start of the import
    if ( !$delta )
    {
        generate_and_import_data( 1, 0, $staging );
    }

    unlink( $dump_file );
}

1;
