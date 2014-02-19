#!/usr/bin/env perl

# generate a report about which media sources have a usable amount of content
# available about the given terms within the given date period.
#
# a report is generated for each tag specified by the --tag option.
# the report is based on all the sentences that match any of the terms
# specified by the --term option.

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Getopt::Long;

use MediaWords::DB;
use MediaWords::Solr;
use MediaWords::Util::SQL;
use MediaWords::Util::CSV;
use MediaWords::Util::Tags;

sub get_tag_media
{
    my ( $db, $tag ) = @_;

    my $media = $db->query( <<END, $tag->{ tags_id } )->hashes;
select m.*
    from media m
        join media_tags_map mtm on ( m.media_id = mtm.media_id )
    where
        mtm.tags_id = ?
    order by m.media_id
END

    return $media;
}

sub get_sentence_count
{
    my ( $medium, $start_date, $end_date, $terms ) = @_;

    my $date_clause = "[${ start_date }T00:00:00Z TO ${ end_date }T00:00:00Z]";

    my $query_params = { fq => [ "media_id:$medium->{ media_id }", "publish_date:${ date_clause }" ], rows => 0 };

    $query_params->{ q } = $terms ? join( ' ', @{ $terms } ) : "*:*";

    my $res = MediaWords::Solr::query( $query_params );

    my $count = $res->{ response }->{ numFound };

    # print STDERR "$medium->{ name } $start_date - $end_date [ $query_params->{ q } ]: $count\n";

    return $count;
}

# get the number of days between the start_date and the end_date
sub get_date_interval
{
    my ( $start_date, $end_date ) = @_;

    my $days = 0;
    while ( MediaWords::Util::SQL::increment_day( $start_date, $days ) lt $end_date )
    {
        $days++;
        die( "dates are more than 365 days apart ($start_date - $end_date )" ) if ( $days > 365 );
    }

    return $days;

}

# return the highest sentence count starting in 2011 from a period of the same length
# as the time between start_date and end_date, from time slices starting at start_date and going
# back
sub get_peak_sentence_count
{
    my ( $medium, $start_date, $end_date, $terms ) = @_;

    my $days = get_date_interval( $start_date, $end_date );

    my $peak_count = 0;
    my ( $slice_start_date, $slice_end_date ) = ( $start_date, $end_date );
    while ( 1 )
    {
        $slice_end_date = MediaWords::Util::SQL::increment_day( $slice_start_date, -1 );
        $slice_start_date = MediaWords::Util::SQL::increment_day( $slice_start_date, ( -1 * $days ) );
        last if ( $slice_start_date lt '2011-01-01' );
        my $slice_count = get_sentence_count( $medium, $slice_start_date, $slice_end_date, $terms );
        $peak_count = ( $slice_count > $peak_count ) ? $slice_count : $peak_count;
    }

    return $peak_count;
}

sub print_media_csv
{
    my ( $media ) = @_;

    my $csv_fields = [
        qw(media_id name url fail absolute fail_absolute percentage fail_percentage absolute_terms fail_absolute_terms percentage_terms fail_percentage_terms)
    ];

    my $hashes = [];
    for my $medium ( @{ $media } )
    {
        my $h = {};

        $h->{ media_id }              = $medium->{ media_id };
        $h->{ name }                  = $medium->{ name };
        $h->{ url }                   = $medium->{ url };
        $h->{ fail_absolute }         = $medium->{ fail_absolute } || 0;
        $h->{ fail_percentage }       = $medium->{ fail_percentage } || 0;
        $h->{ fail_absolute_terms }   = $medium->{ fail_absolute_terms } || 0;
        $h->{ fail_percentage_terms } = $medium->{ fail_percentage_terms } || 0;

        for my $key ( keys( %{ $medium->{ counts } } ) )
        {
            $h->{ $key } = $medium->{ counts }->{ $key };
        }

        push( @{ $hashes }, $h );
    }

    print MediaWords::Util::CSV::get_hashes_as_encoded_csv( $hashes, $csv_fields );
}

# generate the report for the given media tag
sub generate_tag_report
{
    my ( $db, $tag_name, $start_date, $end_date, $terms, $minimums ) = @_;

    my $tag = MediaWords::Util::Tags::lookup_tag( $db, $tag_name );
    die( "Unable to find tag '$tag_name'" ) unless ( $tag );

    my $tag_media = get_tag_media( $db, $tag );

    for my $medium ( @{ $tag_media } )
    {
        $medium->{ counts }->{ absolute } = get_sentence_count( $medium, $start_date, $end_date );
        $medium->{ counts }->{ peak } = get_peak_sentence_count( $medium, $start_date, $end_date );
        $medium->{ counts }->{ absolute_terms } = get_sentence_count( $medium, $start_date, $end_date, $terms );
        $medium->{ counts }->{ peak_terms } = get_peak_sentence_count( $medium, $start_date, $end_date, $terms );

        my $peak_percentage = $medium->{ counts }->{ absolute } / ( $medium->{ counts }->{ peak } || 1 );
        $medium->{ counts }->{ percentage } = sprintf( "%.1f", ( 100 * $peak_percentage ) );

        my $peak_term_percentage = $medium->{ counts }->{ absolute_terms } / ( $medium->{ counts }->{ peak_terms } || 1 );
        $medium->{ counts }->{ percentage_terms } = sprintf( "%.1f", ( 100 * $peak_term_percentage ) );

        print STDERR <<END;
$medium->{ name } 
\ttotal: $medium->{ counts }->{ absolute } / $medium->{ counts }->{ percentage }%
\tterms: $medium->{ counts }->{ absolute_terms } / $medium->{ counts }->{ percentage_terms }%
END

    }

    for my $test ( qw(absolute percentage absolute_terms percentage_terms) )
    {
        print STDERR "\nmedia that with $test sentence count less than $minimums->{ $test }:\n\n";
        for my $medium ( @{ $tag_media } )
        {
            if ( $medium->{ counts }->{ $test } < $minimums->{ $test } )
            {
                print STDERR <<END;
$medium->{ name } 
\ttotal: $medium->{ counts }->{ absolute } / $medium->{ counts }->{ percentage }%
\tterms: $medium->{ counts }->{ absolute_terms } / $medium->{ counts }->{ percentage_terms }%
END
                $medium->{ fail }++;
                $medium->{ "fail_$test" } = 1;
            }
        }
    }

    print STDERR "\nmedia that pass all minimum tests:\n\n";
    for my $medium ( @{ $tag_media } )
    {
        if ( !$medium->{ fail } )
        {
            print STDERR <<END;
$medium->{ name } 
\ttotal: $medium->{ counts }->{ absolute } / $medium->{ counts }->{ percentage }%
\tterms: $medium->{ counts }->{ absolute_terms } / $medium->{ counts }->{ percentage_terms }%
END
        }
    }

    print_media_csv( $tag_media );
}

sub main
{
    my ( $tags, $start_date, $end_date, $terms, $minimums );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Getopt::Long::GetOptions(
        "tag=s@"                 => \$tags,
        "start_date=s"           => \$start_date,
        "end_date=s"             => \$end_date,
        "term=s@"                => \$terms,
        "absolute_min=s"         => \$minimums->{ absolute },
        "percentage_min=s"       => \$minimums->{ percentage },
        "absolute_min_terms=s"   => \$minimums->{ absolute_terms },
        "percentage_min_terms=s" => \$minimums->{ percentage_terms }
    ) || return;

    die( "usage: $0 --tag=<collection:foo> --start_date=<2012-10-01> --end_date=<2012-12-01> --term=<election term>" )
      unless ( $tags && @{ $tags } && $start_date && $end_date && $terms && @{ $terms } );

    die( "invalid start_date: $start_date" ) unless ( $start_date =~ /^\d\d\d\d-\d\d-\d\d$/ );
    die( "invalid end_date: $end_date" )     unless ( $end_date =~ /^\d\d\d\d-\d\d-\d\d$/ );

    my $days = get_date_interval( $start_date, $end_date );

    $minimums->{ absolute }         //= 1000 * $days;
    $minimums->{ percentage }       //= 75;
    $minimums->{ absolute_terms }   //= $minimums->{ absolute } / 100;
    $minimums->{ percentage_terms } //= 75;

    my $db = MediaWords::DB::connect_to_db;

    for my $tag_name ( @{ $tags } )
    {
        generate_tag_report( $db, $tag_name, $start_date, $end_date, $terms, $minimums );
    }
}

main();
