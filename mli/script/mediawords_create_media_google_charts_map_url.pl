#!/usr/bin/perl -w

# create daily_feed_tag_counts table by querying the database tags / feeds / stories

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/.";
}

use MediaWords::DB;
use DBI;
use DBIx::Simple;
use DBIx::Simple::MediaWords;
use Locale::Country;
use URI::Escape;
use List::Uniq ':all';
use List::Util qw (max min reduce sum);
use List::Pairwise qw(mapp grepp map_pairwise);
use URI;
use Data::Dumper;
use Array::Compare;
use Hash::Merge;
use Carp;
use Readonly;
use TableCreationUtils;

#Controls whether we do the
Readonly my $_use_hard_coded_tag_sets_ids => 1;

Readonly my @_default_tag_sets_id => qw (11 13);

sub get_country_code_to_tag_count
{
    my ( $tag_counts ) = @_;

    if ( !$tag_counts->[ 0 ] )
    {
        return;
    }

    my $country_code_count = {};

    for my $tag_count_row ( @{ $tag_counts } )
    {
        my $country_code = uc( Locale::Country::country2code( $tag_count_row->{ tag } ) );

        die unless $country_code;

        #print "Country: $tag_count_row->{tag} country code: $country_code tag count: $tag_count_row->{tag_count} \n";

        if ( defined( $country_code_count->{ $country_code } ) )
        {

            #print "Possibly replacing $country_code on  $tag_count_row->{tag} \n";
        }

        #Some countries can have more than one tag name e.g. "South Korea" and "Republic of Korea"
        #we pick which ever name occurs more
        $country_code_count->{ $country_code } ||= 0;
        $country_code_count->{ $country_code } =
          max( $country_code_count->{ $country_code }, $tag_count_row->{ tag_count } );
    }

    return $country_code_count;
}

sub get_normalized_hash
{
    my ( $hash ) = @_;

    if ( !defined( $hash ) )
    {
        return;
    }

    if ( ( scalar { %$hash } ) == 0 )
    {
        return {};
    }

    my $hash_max = max( values %{ $hash } );

    if ( $hash_max == 0 )
    {
        $hash_max = 1;
    }

    return { mapp { $a => ( ( 100.0 * $b ) / $hash_max ) } %{ $hash } };
}

sub get_percent_country_count_hash
{
    my ( $hash ) = @_;

    $hash = get_normalized_hash( $hash );
    if ( !defined( $hash ) )
    {
        return;
    }

    if ( ( scalar { %$hash } ) == 0 )
    {
        return {};
    }

    my $hash_sum = sum( values %{ $hash } );

    return { mapp { $a => ( ( 100.0 * $b ) / $hash_sum ) } %{ $hash } };

}

# get the url of a chart image for the given tag counts
sub get_tag_count_map_url
{
    my ( $country_code_count, $title ) = @_;

    if ( !defined( $country_code_count ) || !scalar( %{ $country_code_count } ) )
    {
        return;
    }

    my $max_tag_count = max( values %{ $country_code_count } );

    #prevent divide by zero error
    if ( $max_tag_count == 0 )
    {
        $max_tag_count = 1;
    }
    my $data =
      join( ',', map { int( ( $country_code_count->{ $_ } / $max_tag_count ) * 100 ) } sort keys %{ $country_code_count } );
    my $countrycodes = join( '', sort keys %{ $country_code_count } );
    my $esc_title = uri_escape( $title );

    my $url_object = URI->new( 'HTTP://chart.apis.google.com/chart' );

    $url_object->query_form(
        cht  => 't',
        chtm => 'world',
        chs  => '370x190',
        chd  => "t:$data",
        chtt => $title,
        chco => 'ffffff,edf0d4,13390a',
        chld => $countrycodes,
        chf  => 'bg,s,EAF7FE'
    );

    #print Dumper($tag_counts);
    #print Dumper($country_code_count);

    return $url_object->canonical;
}

# get the url of a chart image for the given tag counts
sub get_diff_tag_count_map_url
{
    my ( $country_code_count, $title ) = @_;

    if ( !defined( $country_code_count ) || !scalar( %{ $country_code_count } ) )
    {
        return;
    }

    my $max_tag_count = max( map { abs( $_ ) } values %{ $country_code_count } );

    #prevent divide by zero error
    if ( $max_tag_count == 0 )
    {
        $max_tag_count = 1;
    }
    my $data = join( ',',
        map { int( ( ( $country_code_count->{ $_ } / $max_tag_count ) * 100 ) / 2 ) + 50 }
        sort keys %{ $country_code_count } );
    my $countrycodes = join( '', sort keys %{ $country_code_count } );
    my $esc_title = uri_escape( $title );

    my $url_object = URI->new( 'HTTP://chart.apis.google.com/chart' );

    $url_object->query_form(
        cht  => 't',
        chtm => 'world',
        chs  => '370x190',
        chd  => "t:$data",
        chtt => $title,
        chco => '000000,0000ff,ffffff,00ff00',
        chld => $countrycodes,
        chf  => 'bg,s,EAF7FE'
    );

    #print Dumper($tag_counts);
    #print Dumper($country_code_count);

    return $url_object->canonical;
}

sub grep_media_to_country_code_for_media_type
{

    my ( $db, $media_type, $media_to_country_code_count ) = @_;

    my $media_type_tag_set = 1;

    die unless ( defined( $media_type ) && defined( $media_type_tag_set ) );

    my $media_type_media_ids = $db->query(
"SELECT media_id from media_tags_map, tags where media_tags_map.tags_id=tags.tags_id and tags.tag_sets_id = ? and tags.tag =? order by media_id",
        $media_type_tag_set, $media_type
    )->flat;

    my $is_media_id_media_type = { map { $_ => 1 } @{ $media_type_media_ids } };
    my $media_type_media_country_lists = { grepp { $is_media_id_media_type->{ $a } } %{ $media_to_country_code_count } };
}

sub condence_media_counts
{
    ( my $media_country_tag_counts ) = @_;

    Hash::Merge::specify_behavior(
        {
            'SCALAR' => {
                'SCALAR' => sub { $_[ 0 ] + $_[ 1 ] },
                'ARRAY'  => sub { confess 'type mismatch' },
                'HASH'   => sub {
                    if   ( !defined( $_[ 0 ] ) ) { $_[ 1 ]; }
                    else                         { confess 'type mismatch scalar - hash '; }
                },
            },
            'ARRAY' => {
                'SCALAR' => sub {
                    if   ( !defined( $_[ 1 ] ) ) { $_[ 0 ]; }
                    else                         { confess 'type mismatch array - scalar'; }
                },
                'ARRAY' => sub { [ @{ $_[ 0 ] }, @{ $_[ 1 ] } ] },
                'HASH'  => sub { confess 'type mismatch' },
            },
            'HASH' => {
                'SCALAR' => sub {
                    if   ( !defined( $_[ 1 ] ) ) { $_[ 0 ]; }
                    else                         { confess 'type mismatch hash - scalar'; }
                },
                'ARRAY' => sub { confess 'type mismatch hash - array' },
                'HASH'  => sub { Hash::Merge::_merge_hashes( $_[ 0 ], $_[ 1 ] ) },
            },
        },
        'TYPE_CONSISTENT_SCALAR_ADD',
    );

    #Hsh::Merge::set_behavior('TYPE_CONSISTENT_SCALAR_ADD');

    #my $reduced_list = Hash::Merge::merge( (values %{$media_country_lists})[0], (values%{$media_country_lists})[1]);

    return reduce { Hash::Merge::merge( $a, $b ) } values %{ $media_country_tag_counts };
}

sub get_db_rows_for_media_source_tag_counts
{
    my $ret = [];
    my ( $media_id, $media_source_tag_counts ) = @_;
    for my $tag_sets_id ( sort { $a <=> $b } keys %{ $media_source_tag_counts } )
    {
        my $country_code_to_tag_count = $media_source_tag_counts->{ $tag_sets_id };

        my $chart_url_linear = get_tag_count_map_url( $country_code_to_tag_count, "FOO_BAR" );

        my %country_code_to_log_tag_count = map_pairwise { $a => log( $b ) } %{ $country_code_to_tag_count };

        my $chart_url_log = get_tag_count_map_url( \%country_code_to_log_tag_count, "FOO_BAR" );

        push(
            @{ $ret },
            {
                media_id          => $media_id,
                chart_url         => $chart_url_linear,
                chart_type_is_log => 0,
                tag_sets_id       => $tag_sets_id
            }
        );
        push(
            @{ $ret },
            { media_id => $media_id, chart_url => $chart_url_log, chart_type_is_log => 1, tag_sets_id => $tag_sets_id }
        );
    }

    return $ret;

}

sub get_country_country_difference
{
    my ( $media_source_1_tag_counts, $media_source_2_tag_counts ) = @_;

    Hash::Merge::specify_behavior(
        {
            'SCALAR' => {
                'SCALAR' => sub { $_[ 0 ] - $_[ 1 ] },
                'ARRAY'  => sub { confess 'type mismatch' },
                'HASH'   => sub {
                    if   ( !defined( $_[ 0 ] ) ) { $_[ 1 ]; }
                    else                         { confess 'type mismatch scalar - hash '; }
                },
            },
            'ARRAY' => {
                'SCALAR' => sub { confess 'type mismatch' },
                'ARRAY'  => sub { [ @{ $_[ 0 ] }, @{ $_[ 1 ] } ] },
                'HASH'   => sub { confess 'type mismatch' },
            },
            'HASH' => {
                'SCALAR' => sub {
                    if   ( !defined( $_[ 1 ] ) ) { $_[ 0 ]; }
                    else                         { confess 'type mismatch hash - scalar'; }
                },
                'ARRAY' => sub { confess 'type mismatch hash - array' },
                'HASH'  => sub { Hash::Merge::_merge_hashes( $_[ 0 ], $_[ 1 ] ) },
            },
        },
        'TYPE_CONSISTENT_SCALAR_DIFF',
    );

    return reduce { Hash::Merge::merge( $a, $b ) } ( $media_source_1_tag_counts, $media_source_1_tag_counts );
}

sub percentage_diff
{
    my ( $percent_1, $percent_2 ) = @_;

    my $ret;

    if ( $percent_2 == 0 )
    {
        return 100;
    }

    if ( $percent_1 == 0 )
    {
        return -100;
    }

    if ( $percent_1 > $percent_2 )
    {
        $ret = $percent_2 / $percent_1 * 100;
    }
    elsif ( $percent_1 < $percent_2 )
    {
        $ret = $percent_2 / $percent_1 * 100;
        $ret *= -1;
    }
    else
    {
        $ret = 0;
    }

    return $ret;
}

sub percentage_diff2
{
    my ( $percent_1, $percent_2 ) = @_;

    my $ret;

    $percent_1 ||= 0;
    $percent_2 ||= 0;

    $ret = ( $percent_1 - $percent_2 ) / max( $percent_1, $percent_2 );

    return $ret;
}

sub get_country_percent_ratio_diffs
{
    my ( $country_list_1, $country_list_2 ) = @_;

    my $tmp = {
        map { $_ => percentage_diff2( $country_list_1->{ $_ }, $country_list_2->{ $_ } ) }
        sort ( uniq( keys %$country_list_1, keys %$country_list_2 ) )
    };

    return $tmp;
}

sub out_aggregate_chart_information_and_exit
{

    my ( $db, $media_to_tag_sets_to_country_code_count ) = @_;

    my $newspaper_media_country_lists =
      grep_media_to_country_code_for_media_type( $db, 'newspaper', $media_to_tag_sets_to_country_code_count );
    my $newspapers_aggregate = condence_media_counts( $newspaper_media_country_lists );
    my $db_rows_np = get_db_rows_for_media_source_tag_counts( 'newspapers', $newspapers_aggregate );

    my $blog_media_country_lists =
      grep_media_to_country_code_for_media_type( $db, 'blogs', $media_to_tag_sets_to_country_code_count );
    my $blogs_aggregate = condence_media_counts( $blog_media_country_lists );
    my $db_rows_blogs = get_db_rows_for_media_source_tag_counts( 'blogs', $blogs_aggregate );

#    my $db_rows_diff = get_db_rows_for_media_source_tag_counts( 'newspapers-blogs',  get_country_country_difference(condence_media_counts($blog_media_country_lists),condence_media_counts($newspaper_media_country_lists)));

    my $newspapers_aggregate_calais_counts = $newspapers_aggregate->{ 13 };
    my $blogs_aggregate_calais_counts      = $blogs_aggregate->{ 13 };

    my $chart_url_newspapers_linear = get_tag_count_map_url( $newspapers_aggregate_calais_counts, "FOO_BAR" );

    my $chart_url_blogs_linear = get_tag_count_map_url( $blogs_aggregate_calais_counts, "FOO_BAR" );

    print "Newpapers:\n$chart_url_newspapers_linear\n";
    print "Blogs:\n$chart_url_blogs_linear\n";

    my $country_differences = get_country_percent_ratio_diffs(
        get_percent_country_count_hash( $newspapers_aggregate_calais_counts ),
        get_percent_country_count_hash( $blogs_aggregate_calais_counts )
    );

    my $chart_diff_url_linear = get_diff_tag_count_map_url( $country_differences, "FOO_BAR" );

    print "Newspapers - Blogs:\n$chart_diff_url_linear\n";

    my $ny_times_tag_set_count = $media_to_tag_sets_to_country_code_count->{ 1 }->{ 13 };

    my $ny_times_news_paper_differences = get_country_percent_ratio_diffs(
        get_percent_country_count_hash( $ny_times_tag_set_count ),
        get_percent_country_count_hash( $newspapers_aggregate_calais_counts )
    );

    my $chart_diff_ny_times_newpapers = get_diff_tag_count_map_url( $ny_times_news_paper_differences, "FOO_BAR" );

    print "NY TIMES - Newspapers:\n$chart_diff_ny_times_newpapers\n";

    my $ny_times_blogs_differences = get_country_percent_ratio_diffs(
        get_percent_country_count_hash( $ny_times_tag_set_count ),
        get_percent_country_count_hash( $blogs_aggregate_calais_counts )
    );

    my $chart_diff_ny_times_blogs = get_diff_tag_count_map_url( $ny_times_blogs_differences, "FOO_BAR" );

    print "NY TIMES - Blogs:\n$chart_diff_ny_times_blogs\n";

    print "Newspaper raw count totals:\n";
    print join "\n",
      map { $_ . ',' . $newspapers_aggregate_calais_counts->{ $_ } } sort keys %{ $newspapers_aggregate_calais_counts };
    print "\n";

    print "blog raw count totals:\n";
    print join "\n", map { $_ . ',' . $blogs_aggregate_calais_counts->{ $_ } } sort keys %{ $blogs_aggregate_calais_counts };
    print "\n";

    print "NY TIMES blog count totals:\n";
    print join "\n", map { $_ . ',' . $ny_times_tag_set_count->{ $_ } } sort keys %{ $ny_times_tag_set_count };
    print "\n";

    exit;

    print "<html>\n <body>\n";
    print "<table border='1'>\n";

    my $row_number = 0;
    foreach my $row (
        grep { $_ }
        sort {
                 $a->{ chart_type_is_log } <=> $b->{ chart_type_is_log }
              or $a->{ tag_sets_id } cmp $b->{ tag_sets_id }
              or $a->{ media_id } cmp $b->{ media_id }
        } ( @{ $db_rows_np }, @{ $db_rows_blogs } )
      )
    {
        if ( ( $row_number % 2 ) == 0 )
        {
            print "<tr>\n";
        }
        print( "<td>\n" );
        print "Media Type: $row->{media_id} <br/> ";
        print "Tag Set: " . ( $row->{ tag_sets_id } == 11 ? 'Ny Times ' : $row->{ tag_sets_id } == 13 ? ' Calais' : die );
        print "<br/>\n";
        print "Scaling: " . ( $row->{ chart_type_is_log } ? 'Log' : 'Linear' );
        print "<br/>\n";
        print "\n\t <img src =\"$row->{chart_url}\" /> \n";
        print "</td>\n";

        if ( ( $row_number % 2 ) == 1 )
        {
            print "</tr>\n";
        }

        $row_number++;
    }

    print "</table>\n";
    print "</body>\n";
    print "</html>\n";
    exit;

    print Dumper (
        get_db_rows_for_media_source_tag_counts( 'newspapers', condence_media_counts( $newspaper_media_country_lists ) ) );
    print Dumper ( get_db_rows_for_media_source_tag_counts( 'blogs', condence_media_counts( $blog_media_country_lists ) ) );

    exit;
}

sub main
{
    my $table_name      = "media_google_charts_map_url";
    my $temp_table_name = $table_name . time();

    my $db = TableCreationUtils::get_database_handle();

    my @media_ids = $db->query( "select media_id from media order by media_id" )->flat;

    my @tag_set_ids;
    if ( !$_use_hard_coded_tag_sets_ids )
    {
        @tag_set_ids = $db->query( " select distinct(tag_sets_id) from media_tag_counts order by tag_sets_id" )->flat;
    }
    else
    {
        @tag_set_ids = @_default_tag_sets_id;
    }
    my @rows_to_insert;

    my $i = 0;

   #TODO this is a hack to make calais happy...
   #Calais only recognizes iran as 'islamic republic of iran' but Locale::County wants 'iran, islamic republic of' and 'iran;
    Locale::Country::rename_country( 'ir' => 'Islamic Republic of Iran' );

    #similar issue
    Locale::Country::rename_country( 'cd' => 'Democratic Republic of Congo' );

    my @all_countries = map { lc } Locale::Country::all_country_names;

#handle common country names that are not the default in ISO 3166
# To regenerate this list grab the data segment from run Locale/Country.pm in cpan source and save it too country_code_list.txt
#then run:
#cat country_code_list.txt  | sed -e 's/\w*:\w*:\w*:[^:]*//' | uniq |  tr ':' '\n' | grep -v '^$' | sort | perl -e 'while (<>) { chomp; print "\"$_\",\n"; } ' | tr \" \'
    my @alternate_country_names = (

        'British Virgin Islands',
        'Burma',
        'Congo, Democratic Republic of the',
        'Congo, Republic of the',
        'East Timor',
        'Falkland Islands (Islas Malvinas)',
        'French Southern and Antarctic Lands',
        'Great Britain',
        'Holy See (Vatican City)',
        'Iran',
        'Jan Mayen',
        'Kazakstan',
        'Korea, North',
        'Korea, South',
        'Libya',
        'Macau',
        'Macedonia',
        'Macedonia, Former Yugoslav Republic of',
        'Moldova',
        'North Korea',
        'Pitcairn Island',
        'Russia',
        'South Korea',
        'Svalbard',
        'Syria',
        'Taiwan',
        'Tanzania',
        'United States of America',
        'USA',
        'Yugoslavia',
        'Zaire',
    );

    @alternate_country_names = map { lc } @alternate_country_names;
    @all_countries = ( @all_countries, @alternate_country_names );
    @all_countries = uniq( @all_countries );

    #print "countries: ";
    #print join ", ", @all_countries;
    #print "\n";

    my $media_to_country_code_count = {};

    foreach my $media_id ( sort { $a <=> $b } @media_ids )
    {
        $i++;
        print STDERR "media_id: $media_id  ($i of " . @media_ids . ") \n";

        foreach my $tag_sets_id ( @tag_set_ids )
        {
            my @media_tag_counts = (
                $db->query(
                    "select c.*, t.tag from media_tag_counts c, tags t " . "where c.tags_id = t.tags_id and c.media_id = " .
                      ( $media_id + 0 ) . " and t.tag_sets_id = " . ( $tag_sets_id + 0 ) . " and  t.tag in (??) " .
                      " order by t.tag, c.tag_count desc",
                    @all_countries
                  )
                  || die $db->error
            )->hashes;

            #print Dumper ( @media_tag_counts );

            my $country_code_to_tag_count = get_country_code_to_tag_count( \@media_tag_counts );

            #print Dumper ($country_code_to_tag_count);

            #$country_code_to_tag_count = get_normalized_hash($country_code_to_tag_count);
            $media_to_country_code_count->{ $media_id }->{ $tag_sets_id } = $country_code_to_tag_count;
        }
    }

    my $media_country_lists = $media_to_country_code_count;

    #out_aggregate_chart_information_and_exit($db,$media_country_lists);

    my @rows_to_insert_2;

    for my $media_id ( sort { $a <=> $b } keys %{ $media_country_lists } )
    {

        my $media_source_tag_counts = $media_country_lists->{ $media_id };
        my $new_rows = get_db_rows_for_media_source_tag_counts( $media_id, $media_source_tag_counts );

        push @rows_to_insert_2, @{ $new_rows };
    }

    $db->query( "DROP TABLE if exists $temp_table_name" );    # or warn $db->error;
    $db->query( "CREATE TABLE $temp_table_name ( " . "  media_id integer NOT NULL REFERENCES media ON DELETE CASCADE" .
          ", tag_sets_id integer NOT NULL REFERENCES  media ON DELETE CASCADE" . ", chart_type_is_log  BOOLEAN NOT NULL" .
          ", chart_url text) " )
      or die $db->error;

    $i = 0;
    foreach my $row_to_insert ( @rows_to_insert_2 )
    {
        $i++;
        print "inserting row $i of  " . @rows_to_insert_2 . "\n";

        #my @value = %{$row_to_insert};
        #print join ' ,' , @value;
        #print "\n";

        $db->query(
            " insert into $temp_table_name (media_id, tag_sets_id, chart_type_is_log, chart_url) VALUES (??)",
            $row_to_insert->{ media_id },
            $row_to_insert->{ tag_sets_id },
            $row_to_insert->{ chart_type_is_log },
            $row_to_insert->{ chart_url },
        );
    }

    print "creating indices ...\n";

    #	print "create index media_id_index on $temp_table_name (media_id)\n";

    my $now = time();

    $db->query( "drop index if exists " . $table_name . "_media_id_index_$now" );
    $db->query( "create index " . $table_name . "_media_id_index_$now on $temp_table_name (media_id)" );

    $db->query( "drop index if exists " . $table_name . "_media_id_tag_sets_id_index_$now" );
    $db->query(
        "create index " . $table_name . "_media_id_tag_sets_id_index_$now on $temp_table_name (media_id, tag_sets_id)" );

    print "replacing table ...\n";
    $db->begin_work();
    $db->query( "drop table if exists $table_name" );
    $db->query( "alter table $temp_table_name rename to $table_name" );
    $db->commit;

    $db->query( "analyze $table_name" );
    print "completed table update\n";
}

main();
