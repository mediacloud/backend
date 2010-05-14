package MediaWords::Util::Chart;

use strict;

use Time::Local;
use URI::Escape;

# STATICS

# cache google encoding lookup table
my $_google_chart_simple_encoding_lookup;

# INTERNAL FUNCTIONS

# get lookup table for google chart simple encoding values
# http://code.google.com/apis/chart/formats.html#simple
sub _get_google_chart_simple_encoding_lookup
{
    if ( !$_google_chart_simple_encoding_lookup )
    {
        my $i = 0;
        for my $c ( ( 'A' .. 'Z' ), ( 'a' .. 'z' ), ( 0 .. 9 ) )
        {
            $_google_chart_simple_encoding_lookup->{ $i++ } = $c;
        }
    }

    return $_google_chart_simple_encoding_lookup;
}

# take a date in the form '2008-09-01' and add one day
sub _add_one_day
{
    my ( $d ) = @_;

    my ( $year, $month, $day ) = split( '-', $d );

    my @t = localtime( timelocal( 0, 0, 0, $day, $month - 1, $year - 1900 ) + 86400 );

    return sprintf( '%04d-%02d-%02d', $t[ 5 ] + 1900, $t[ 4 ] + 1, $t[ 3 ] );
}

# PUBLIC FUNCTIONS

# generate the google chart url for a timeline of story term counts
# eg:
#http://chart.apis.google.com/chart?&cht=ls&chd=t:0,30,60,70,90,95,100|20,30,40,50,60,70,80|10,30,40,45,52&chco=ff0000,00ff00,0000ff&chs=250x150&chdl=NASDAQ|FTSE100|DOW
#
# where dates is a list of dates: [ '2008-08-01', '2008-08-08', '2008-08-15' ]
# terms is a list of terms: [ 'obama', 'mccain' ]
# and term_date_counts is a matric of data by term / date: [ [ 1, 2, 3 ], [ 4, 5, 6 ] ]
sub generate_line_chart_url
{
    my ( $dates, $terms, $term_date_counts ) = @_;

    my $params = [];

    # data scaling
    my $max = 1;
    for my $counts ( @{ $term_date_counts } )
    {
        for my $count ( @{ $counts } )
        {
            if ( !$max || ( $count > $max ) )
            {
                $max = $count;
            }
        }
    }

    # data
    # normalize to 60 to be able to use simple encoding (which we need to be able to fit all the data into the url)
    my $enc = _get_google_chart_simple_encoding_lookup();
    push(
        @{ $params },
        'chd=s:' . join(
            ',',
            map
            {
                join( '', map { $enc->{ int( $_ * ( 60 / $max ) ) } } @{ $_ } )
              } @{ $term_date_counts }
        )
    );

    # legend for lines
    push( @{ $params }, 'chdl=' . join( '|', map { s/\|/-/g; uri_escape_utf8( $_ ); } @{ $terms } ) );

    # legend for x axis
    my $days;
    if ( @{ $dates } <= 4 )
    {
        $days = $dates;
    }
    else
    {
        for ( my $n = 0 ; $n < 3 ; $n++ )
        {
            my $i = $n * ( @{ $dates } / 3 );
            push( @{ $days }, $dates->[ int( $i ) ] );
        }
        push( @{ $days }, $dates->[ $#{ $dates } ] );
    }

    push( @{ $params }, 'chxt=x&chxl=0:|' . join( '|', @{ $days } ) );

    # size
    push( @{ $params }, 'chs=600x250' );

    # type
    push( @{ $params }, 'cht=lc' );

    # color
    my $colors = [ qw(ff0000 00ff00 0000ff ff8888 88ff88 8888ff 88ffff ff88ff ffff88 888888) ];
    while ( @{ $colors } > @{ $terms } )
    {
        pop( @{ $colors } );
    }
    push( @{ $params }, 'chco=' . join( ',', @{ $colors } ) );

    my $url = 'http://chart.apis.google.com/chart?' . join( '&', @{ $params } );

    #print STDERR "google chart url: $url\n";

    return $url;
}

# get a google chart url for up to 10 of the given words for the current media set
#
# db is a dbis connection
# media_set that points to the set of media to include
# start_date is the start date for the chart: '2008-08-01'
# num_days is the number of days to increment past start_date: 7
# words is a list of words: [ { stem => 'foo', term => 'foos' }, ... ]
sub get_daily_term_chart_url
{
    my ( $db, $media_set, $start_date, $num_days, $words, $dashboard_topic_clause ) = @_;

    my $dates = [ $start_date ];
    for my $i ( 2 .. $num_days )
    {
        push( @{ $dates }, _add_one_day( $dates->[ $#{ $dates } ] ) );
    }

    die "no words " unless scalar( @{ $words } ) > 0;

    if ( @{ $words } > 10 )
    {
        $words = [ @{ $words }[ 0 .. 9 ] ];
    }

    my $terms            = [];
    my $term_date_counts = [];

    my $date_list = join( ',', map { $db->dbh->quote( $_ ) . "::date" } @{ $dates } );
    my $stem_list = join( ',', map { $db->dbh->quote( $_->{ stem } ) } @{ $words } );

    # query everything at once and then go back to make sense of it because it is a couple of orders
    # of magnitude faster to do just one query than lots of little queries
    my $counts = $db->query(
        "select publish_day, stem, " .
          "    ( least( 0.10, sum(stem_count)::float / sum(total_count)::float ) * count(*) * 100000 ) " .
          "      as stem_count " . "  from daily_words_with_totals " . "  where publish_day in ( $date_list ) " .
          "    and media_sets_id = ? " . "    and stem in ( $stem_list ) " . "    and $dashboard_topic_clause " .
          "  group by stem, publish_day " . "  order by stem, publish_day",
        $media_set->{ media_sets_id }
    )->hashes;

    my $stem_date_lookup;
    for my $count ( @{ $counts } )
    {
        my $date = substr( $count->{ publish_day }, 0, 10 );
        $stem_date_lookup->{ $count->{ stem } }->{ $date } = $count->{ stem_count };
    }

    for my $word ( @{ $words } )
    {
        push( @{ $terms }, $word->{ term } );

        my $counts;
        for my $date ( @{ $dates } )
        {
            push( @{ $counts }, $stem_date_lookup->{ $word->{ stem } }->{ $date } || 0 );
        }

        push( @{ $term_date_counts }, $counts );
    }

    my $url = generate_line_chart_url( $dates, $terms, $term_date_counts );

    return $url;
}

1;
