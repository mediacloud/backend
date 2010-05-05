#!/usr/bin/perl -w

# create daily_feed_tag_counts table by querying the database tags / feeds / stories

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
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
use URI::Split;
use Data::Dumper;
use Array::Compare;
use Hash::Merge;
use Carp;
use Readonly;
use TableCreationUtils;

sub main
{
    my $db = TableCreationUtils::get_database_handle();

    while ( my $spider_url = <> )
    {
        chomp($spider_url);
        my $hashes = $db->query( 'select * from downloads where url=? and type=\'spider_blog_home\'', $spider_url )->hashes;

        my $download_exists = scalar(@$hashes) > 0;

        if ( !$download_exists )
        {
            print "adding '$spider_url'\n";
            $db->create(
                'downloads',
                {
                    url  => $spider_url,
                    host => lc( ( URI::Split::uri_split($spider_url) )[1] ),

                    #                stories_id    => 1,
                    type          => 'spider_blog_home',
                    sequence      => 0,
                    state         => 'pending',
                    priority      => 1,
                    download_time => 'now()',
                    extracted     => 'f'
                }
            );

        }
        else
        {
            print "not adding '$spider_url'\n";
        }
    }
}

main();
