package MediaWords::DBI::Feeds;

# helper functions for feeds

use strict;

use Encode;
use LWP::Simple;
use URI::Split;
use XML::Entities;
use XML::Feed;

# parse out the generator 
sub get_generator_from_xml 
{
    #my ($xml) = @_;
    
    
    if ($_[0] =~ /generator>([^<]*)</) {
        return XML::Entities::decode('all', $1);
    }

    return undef;
}

# parse out the first item.comments field
sub get_comments_archive_from_xml 
{
    #my ($xml) = @_;
    
    if ($_[0] =~ /comments>[^<]*#([^<]*)</) {
        return XML::Entities::decode('all', $1);
    }

    return undef;
}

# get a list of all date since 2008-04-01 in 2008/04/01 and 2008-04-01 format
sub _get_archive_dates 
{
    my $dates = [];
    for ( my $date = Time::Local::timelocal(0, 0, 0, 1, 3, 108); $date < time(); $date += 86400 ) 
    {
        my ($sec, $min, $hour, $mday, $mon, $year) = localtime($date);
        push(@{$dates}, sprintf('%04d/%02d/%02d', $year + 1900, $mon + 1, $mday));
    }
    
    return $dates;    
}

# validate that url points to a valid rss or atom feed.
# takes either a reference to the xml content or a url to download
sub parse_feed 
{
    my ($xml_ref) = @_;
    
    if (!ref($xml_ref)) {
        print "fetching: $xml_ref ... ";
        my $xml = LWP::Simple::get($xml_ref);
        if (!$xml) {
            print "failed\n";
            return undef;
        }
        print "done\n";
        $xml_ref = \$xml;
    }
    
    my $feed;
    eval { $feed = XML::Feed->parse($xml_ref); };

    my $err = $@;
    
    # try to reparse after munging the xml.  only do this when needed to avoid expensive regexes.
    if ($err)
    {
        $$xml_ref = encode( 'utf-8', $$xml_ref );
        $$xml_ref =~ s/[\s\n\r]+/ /g;
        $$xml_ref =~ s/<!--[^>]*-->//g;
        $$xml_ref =~ s/><rss/>\n<rss/;
        eval { $feed = XML::Feed->parse($xml_ref); };
        $err = $@;
    }
    
    # if ($err) {
    #     print "error: $err\n";
    # }
        
    return $feed;
}

# try to find archives for the feed and add pending downloads for them
sub add_archive_feed_downloads
{
    my ($db, $feed) = @_;
    
    my $feed_url = $feed->{url};
 
    my $archive_dates = _get_archive_dates();
 
    my $current_year = sprintf("%04d", (localtime())[5] + 1900);
 
    my $archive_urls = [];
    if ( ($feed_url =~ /(.*)(\?.*feed=.*)/) || ($feed_url =~ /(http:\/\/.*)\/(feed\/?.*)/) )
    {
        my ($base, $path) = ($1, $2);

        my $sample_date = $archive_dates->[@{$archive_dates} - 1];
        if (parse_feed("${base}/${current_year}/${path}")) {
            push( @{$archive_urls}, map { "${base}/" . $_ . "/${path}" } @{$archive_dates} );
        }
    }

    if (@{$archive_urls}) {
        print "archive " . @{$archive_urls} . " urls ...\n";
    }

    for my $url (@{$archive_urls}) {
        $db->query("insert into downloads (feeds_id, url, host, download_time, type, state, priority, sequence, extracted) " .
                   "values(?, ?, ?, now(), ?, ?, ?, ?, ?)",
                   $feed->{feeds_id}, $url, lc( ( URI::Split::uri_split($url) )[1] ), 'feed', 'pending', 10, 1, 'f');
    }
}

1;