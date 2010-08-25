#!/usr/bin/perl

# import list of spidered russian blogs from csv

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Date::Parse;
use HTTP::Request;
use LWP::UserAgent;
use Text::CSV_XS;
use Text::Trim;

use DBIx::Simple::MediaWords;
use Feed::Scrape;
use MediaWords::DB;
use Perl6::Say;
use Data::Dumper;

sub _feed_item_age
{
    my ( $item ) = @_;

    return ( time - Date::Parse::str2time( $item->pubDate ) );
}

sub _is_recently_updated
{
    my ( $medium_url, $feed_url ) = @_;

    my $medium;

#    my $response = LWP::UserAgent->new()->request( HTTP::Request->new( GET => $feed_url ) );
    my $response = LWP::UserAgent->new( agent => 'Firefox/3.0.11')->request( HTTP::Request->new( GET => $feed_url ) );

    

    if ( !$response->is_success )
    {
       my $retry_count = 0;

       while ($retry_count <= 9 && !$response->is_success)
       {
	   print STDERR "Retrying fetch of '$feed_url' ($medium_url): " . $response->status_line . "\n";
	  $response = LWP::UserAgent->new->request( HTTP::Request->new( GET => $feed_url ) );

	  
	  $retry_count++;
       }
    }

    if ( !$response->is_success )
    {
        print STDERR "Unable to fetch '$feed_url' ($medium_url): " . $response->status_line . "\n";
        return;
    }

    if ( !$response->decoded_content )
    {

        #say STDERR "No content in feed";
        return;
    }

    my $feed = Feed::Scrape->parse_feed( $response->decoded_content );

    my $medium_name;
    if ( $feed )
    {
        $medium_name = $feed->title;
    }
    else
    {
        print STDERR "Unable to parse feed '$feed_url' ($medium_url)\n";
        $medium_name = $medium_url;
        return;
    }

    my $last_post_date = 0;

    my $days = 60;
    my $seconds_per_day =  60 * 60 * 24;
    my $age_in_seconds = $days * $seconds_per_day;

    my @recent_items = grep { _feed_item_age( $_ ) < ( $age_in_seconds ) } $feed->get_item;

    if ( scalar( @recent_items ) >= 2 )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

sub derive_feed_url
{
    ( my $row ) = @_;

    my $feed_url = $row->{ rss } || $row->{ feedurl };

    return $feed_url if $feed_url;

    #next if ! $feed_url;

    my $source = $row->{ url } || $row->{ source };

    my $host = $source;
    $host =~ s/http:\/\/((.*\.)*)([^.\/]+\.((co\.uk)|([^.\/]+)))\/?.*/$3/;

    my $link = $row->{ link };

    if ( $host eq 'livejournal.com' )
    {

        #next unless $row->{source} eq "http://users.livejournal.com";

        if ( $row->{ source } eq "http://users.livejournal.com" )
        {
            $feed_url = $link;
            $feed_url =~ s/users\.livejournal\.com\/([^\/]*)\/.*/users\.livejournal\.com\/$1\/data\/atom/;
        }
        else
        {
            $feed_url = "$row->{source}/data/atom";
        }

        #next;
        #next if  "$row->{source}/data/atom" eq $feed_url;
        #say "$row->{source} $feed_url $row->{link}";
    }

    return $feed_url;
}

sub main
{
    my ( $file, $out_file ) = @ARGV;

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    if ( !$file || !$out_file )
    {
        die( "usage: mediawords_find_recently_updated_blogs.pl <csv file> <output file>\n" );
    }

    my $csv = Text::CSV_XS->new( { binary => 1 } ) || die "Cannot use CSV: " . Text::CSV_XS->error_diag();

    open( my $fh, "<:encoding(utf8)", $file ) or die "Unable to open file $file: $!\n";

    open( my $out_fh, ">:encoding(utf8)", $out_file ) or die "Unable to create file $out_file: $!\n";

    my $header_line = $csv->getline( $fh );
    $csv->column_names( $header_line );

    $csv->print( $out_fh, $header_line );
    say $out_fh;

    my $media_added = 0;

    my $rows_processed = 0;

    my $recent_blogs = 0;
    my $old_blogs    = 0;

    while ( my $colref = $csv->getline( $fh ) )
    {

        my %hr;
        @hr{ @{ $csv->{ _COLUMN_NAMES } } } = @$colref;

        my $row = \%hr;

        my $media_url = $row->{ url } || $row->{ source };

        my $feed_url = $row->{ rss } || $row->{ feedurl };

        if ( !$feed_url )
        {
            $feed_url = derive_feed_url( $row );
        }

        if ( _is_recently_updated( $media_url, $feed_url ) )
        {
            print STDERR "Recent blog $media_url $feed_url \n";

            #print STDERR "BLOGS ADDED: " . ++$media_added . "\n";
            $csv->print( $out_fh, $colref );
            say $out_fh;

            $recent_blogs++;
        }
        else
        {
            $old_blogs++;

            print STDERR "Old blog $media_url $feed_url \n";
        }

        $rows_processed++;

        #if ( $rows_processed > 100 )
        #{
        #    last;
        #}
    }

    say "Recent blogs $recent_blogs Old_blogs: $old_blogs";

}

main();

__END__
