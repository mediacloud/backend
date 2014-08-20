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
use Getopt::Long;
use Text::CSV;
use Scalar::Util qw(looks_like_number);
use Readonly;
use DateTime;
use Data::Dumper;

Readonly my $sleep_between_links => 1;    # seconds

sub process_csv_stories($;$$)
{
    my ( $stories_csv_file, $stat_only, $no_sleep_between_links ) = @_;

    $stat_only              //= 0;
    $no_sleep_between_links //= 0;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    unless ( -f $stories_csv_file )
    {
        die "File '$stories_csv_file' does not exist.\n";
    }

    my $csv = Text::CSV->new( { binary => 1 } )    # should set binary attribute.
      or die "Cannot use CSV: " . Text::CSV->error_diag();

    my %stats = (
        links_total => 0,
        links_found => 0,

        links_that_have_clicks     => 0,
        links_that_have_categories => 0,
        links_that_have_referrers  => 0,
        links_that_have_shares     => 0,
    );

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

        ++$stats{ links_total };

        my $link_lookup;
        eval { $link_lookup = MediaWords::Util::Bitly::bitly_link_lookup_hashref_all_variants( $stories_url ); };
        if ( $@ or ( !$link_lookup ) )
        {
            warn "Unable to lookup story with URL $stories_url: $@";
            next;
        }
        say STDERR "Link lookup: " . Dumper( $link_lookup );

        # Fetch link information for all Bit.ly links at once
        my $bitly_info = {};
        unless ( $stat_only )
        {
            my $bitly_ids = [ grep { defined $_ } values %{ $link_lookup } ];

            say STDERR "\tFetching info for Bit.ly IDs " . join( ', ', @{ $bitly_ids } ) . "...";
            if ( scalar( @{ $bitly_ids } ) )
            {
                eval { $bitly_info = MediaWords::Util::Bitly::bitly_info_hashref( $bitly_ids ); };
                if ( $@ or ( !$bitly_info ) )
                {
                    warn "Unable to fetch Bit.ly info for Bit.ly IDs " . join( ', ', @{ $bitly_ids } ) . ": $@";
                    next;
                }
            }

            # say STDERR "Link info: " . Dumper( $bitly_info );
        }

        # Found links statistics
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
            ++$stats{ links_found };
        }

        # Stop here if only querying for Bit.ly links was needed
        unless ( $stat_only )
        {
            my $link_stats = {};

            my %at_least_one_link_has = (
                clicks     => 0,
                categories => 0,
                referrers  => 0,
                shares     => 0,
            );

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

                $link_stats->{ 'data' }->{ $bitly_id } = {
                    'url'        => $link,
                    'info'       => $bitly_info->{ $bitly_id },
                    'categories' => MediaWords::Util::Bitly::bitly_link_categories( $bitly_id ),
                    'clicks'     => [

                        # array because one might want to make multiple requests with various dates
                        MediaWords::Util::Bitly::bitly_link_clicks( $bitly_id )
                    ],
                    'referrers' => [

                        # array because one might want to make multiple requests with various dates
                        MediaWords::Util::Bitly::bitly_link_referrers( $bitly_id )
                    ],
                    'shares' => [

                        # array because one might want to make multiple requests with various dates
                        MediaWords::Util::Bitly::bitly_link_shares( $bitly_id )
                    ],
                };

                # Collect stats
                foreach my $click ( @{ $link_stats->{ 'data' }->{ $bitly_id }->{ 'clicks' }->[ 0 ]->{ 'link_clicks' } } )
                {
                    if ( $click->{ 'clicks' } > 0 )
                    {
                        $at_least_one_link_has{ clicks } = 1;
                        last;
                    }
                }
                if ( scalar @{ $link_stats->{ 'data' }->{ $bitly_id }->{ 'categories' } } > 0 )
                {
                    $at_least_one_link_has{ categories } = 1;
                }
                foreach my $referrer ( @{ $link_stats->{ 'data' }->{ $bitly_id }->{ 'referrers' }->[ 0 ]->{ 'referrers' } } )
                {
                    if ( $referrer->{ 'clicks' } > 0 )
                    {
                        $at_least_one_link_has{ referrers } = 1;
                        last;
                    }
                }
                if ( scalar @{ $link_stats->{ 'data' }->{ $bitly_id }->{ 'shares' }->[ 0 ]->{ 'shares' } } > 0 )
                {
                    $at_least_one_link_has{ shares } = 1;
                }

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

            if ( $at_least_one_link_has{ clicks } )
            {
                ++$stats{ links_that_have_clicks };
            }
            if ( $at_least_one_link_has{ categories } )
            {
                ++$stats{ links_that_have_categories };
            }
            if ( $at_least_one_link_has{ referrers } )
            {
                ++$stats{ links_that_have_referrers };
            }
            if ( $at_least_one_link_has{ shares } )
            {
                ++$stats{ links_that_have_shares };
            }

        }

        unless ( $no_sleep_between_links )
        {
            say STDERR "Sleeping for rate limiting reasons...";
            sleep( $sleep_between_links + 0 );
        }
    }
    $csv->eof or $csv->error_diag();
    close $fh;

    say STDERR "Total links: $stats{ links_total }";
    say STDERR "Found links: $stats{ links_found }";

    unless ( $stat_only )
    {
        say STDERR "Links that have:";
        say STDERR "    * clicks: $stats{ links_that_have_clicks }";
        say STDERR "    * categories: $stats{ links_that_have_categories }";
        say STDERR "    * referrers: $stats{ links_that_have_referrers }";
        say STDERR "    * shares: $stats{ links_that_have_shares }";
    }
}

sub main()
{
    Readonly my $usage => "Usage: $0 --stories_csv_file=stories.csv [--stat_only] [--no_sleep_between_links]";

    my $stories_csv_file       = undef;
    my $stat_only              = 0;
    my $no_sleep_between_links = 0;

    GetOptions(
        "stories_csv_file=s"     => \$stories_csv_file,
        "stat_only"              => \$stat_only,
        "no_sleep_between_links" => \$no_sleep_between_links
    ) or die $usage;
    unless ( $stories_csv_file )
    {
        die $usage;
    }

    say STDERR "starting -- " . localtime();

    say STDERR "Stories CSV file: $stories_csv_file";
    say STDERR "Only check if Bit.ly links exist and don't fetch stats: " . ( $stat_only ? 'yes' : 'no' );
    say STDERR "Don't sleep($sleep_between_links) between analyzing links: " . ( $no_sleep_between_links ? 'yes' : 'no' );

    process_csv_stories( $stories_csv_file, $stat_only, $no_sleep_between_links );

    say STDERR "finished -- " . localtime();
}

main();
