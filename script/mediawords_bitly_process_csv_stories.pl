#!/usr/bin/env perl
#
# Process CSV list stories against Bit.ly API
#
#
# Usage
# =====
#
#     ./script/run_with_carton.sh ./script/mediawords_bitly_process_csv_stories.pl stories.csv
#
# stories.csv should contain stories_id and URL as such:
#
#    183045817,http://www.iol.co.za/safa-remember-madiba-magic-1.1617700
#    193464034,http://armenpress.am/arm/news/745942/
#    ...
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Bitly;
use Text::CSV;
use Scalar::Util qw(looks_like_number);
use Readonly;
use DateTime;
use Data::Dumper;

sub main()
{
    unless ( $ARGV[ 0 ] )
    {
        die "Usage: $0 stories.csv\n";
    }

    my $stories_csv_file = $ARGV[ 0 ];
    unless ( -f $stories_csv_file )
    {
        die "File '$stories_csv_file' does not exist.\n";
    }

    my $csv = Text::CSV->new( { binary => 1 } )    # should set binary attribute.
      or die "Cannot use CSV: " . Text::CSV->error_diag();

    my $links_total = 0;
    my $links_found = 0;

    open my $fh, "<:encoding(utf8)", $stories_csv_file or die "Unable to open $stories_csv_file: $!";
    while ( my $row = $csv->getline( $fh ) )
    {
        if ( scalar( @{ $row } ) != 2 )
        {
            die "Only two columns with stories_id and URL is expected; got: " . Dumper( $row );
        }

        my $stories_id  = $row->[ 0 ];
        my $stories_url = $row->[ 1 ];

        unless ( looks_like_number( $stories_id ) )
        {
            die "The first column doesn't look like stories_id; got: " . Dumper( $row );
        }

        say STDERR "Processing story $stories_id...";

        ++$links_total;

        Readonly my $link_lookup => MediaWords::Util::Bitly::bitly_link_lookup_all_variants( $stories_url );
        say STDERR "Link lookup: " . Dumper( $link_lookup );

        my $link_stats = {};

        # Fetch Bit.ly stats for the link (if any)
        foreach my $link ( keys %{ $link_lookup } )
        {

            unless ( defined $link_lookup->{ $link } )
            {
                next;
            }

            unless ( defined $link_stats->{ 'data' } )
            {
                $link_stats->{ 'data' } = {};
            }

            my $bitly_id = $link_lookup->{ $link };

            say STDERR "\tFetching stats for Bit.ly ID $bitly_id...";
            if ( $link_stats->{ 'data' }->{ $bitly_id } )
            {
                die "Bit.ly ID $bitly_id already exists in link stats hashref: " . Dumper( $link_stats );
            }

            my $bitly_clicks = MediaWords::Util::Bitly::bitly_link_clicks( $bitly_id );

            my $bitly_category = MediaWords::Util::Bitly::bitly_link_category( $bitly_id );

            my $bitly_referrers = MediaWords::Util::Bitly::bitly_link_referrers( $bitly_id );

            $link_stats->{ 'data' }->{ $bitly_id } = {
                'url'    => $link,
                'clicks' => [

                    # array because one might want to make multiple requests with various dates
                    $bitly_clicks

                ],

                'category' => $bitly_category,

                'referrers' => [

                    # array because one might want to make multiple requests with various dates
                    $bitly_referrers,

                  ]

                  # 'shares' => $bitly_shares
            };

        }

        # No links?
        if ( scalar( keys %{ $link_stats } ) )
        {

            # Store timestamp (GMT, not local time)
            $link_stats->{ 'timestamp' } = time();

        }
        else
        {

            # Mark as "not found"
            $link_stats->{ 'error' } = 'NOT_FOUND';
        }

        say STDERR "Link stats: " . Dumper( $link_stats );

        my $link_was_found = 0;
        foreach my $link ( keys %{ $link_lookup } )
        {
            if ( defined $link_lookup->{ $link } )
            {
                $link_was_found = 1;
                last;
            }
        }
        if ( $link_was_found )
        {
            ++$links_found;
        }

        say STDERR "Done.";
    }
    $csv->eof or $csv->error_diag();
    close $fh;

    say STDERR "Total links: $links_total";
    say STDERR "Found links: $links_found";
}

main();
