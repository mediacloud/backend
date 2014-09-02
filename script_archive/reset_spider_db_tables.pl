#!/usr/bin/env perl

# create daily_feed_tag_counts table by querying the database tags / feeds / stories

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/.";
}

use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use DBI;
use DBIx::Simple;
use DBIx::Simple::MediaWords;
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

#use TableCreationUtils;
use Term::Prompt;

my @_spider_urls = (

    #                        'http://loveplanet.ru/a-ljpost/login-nemchiner/',
    #                        'http://flat1k.blog.ru',
    #                        'http://www.babyblog.ru/user/Soullove',
    #                        'http://blogs.privet.ru/user/dasha_redd',
    #                        'http://tema.livejournal.com',
    #                        'http://abpaximov.livejournal.com',
    #                        'http://radulova.livejournal.com',
    #                        'http://katoga.livejournal.com',
    #                        'http://golubchikav.livejournal.com',
    #                        'http://blogs.mail.ru/mail/vrs63',
    #                        'http://blogs.mail.ru/mail/elektromonter500',
    #                        'http://kvadroleshiy84.ya.ru',
    #                        'http://nastya-slastya2.ya.ru',
    #                        'http://logunova2727k.ya.ru',
    #                        'http://www.24open.ru/puzik2005/blog/',
    #                        'http://www.24open.ru/Kera666/blog',
    #                        'http://www.24open.ru/Olwga3502818/blog',
    #                        'http://www.24open.ru/Marinna3580273/blog',
    #                        'http://www.diary.ru/~madrak',
    #                        'http://www.diary.ru/~hoshizora',
    #                        'http://www.diary.ru/~diary-spirit',
    #                        'http://www.diary.ru/~lexiff',
    #                        'http://www.diary.ru/~Corona-del-Norte',
    #                        'http://www.liveinternet.ru/users/1337200',
    #                        'http://www.liveinternet.ru/users/afina74',
    #                        'http://www.liveinternet.ru/users/radioheads',
);

sub main
{

    my $warning_message =
      "Warning running this script will effectively delete all spidering results. Are you sure you wish to continue?";

    my $continue_and_reset_db = &prompt( "y", $warning_message, "", "n" );

    exit if !$continue_and_reset_db;

    my $db = TableCreationUtils::get_database_handle();

    #$db->query("ALTER table downloads ALTER column feeds_id DROP NOT NULL;");

    $db->query( "DELETE FROM downloads where (type::text) like 'spider%'; " );
    $db->query( "DROP INDEX  if exists spider_urls" );

    #$db->query("CREATE INDEX spider_urls_2 on downloads (url) where type::text like 'spider%' ");

    $db->query( "DROP TABLE if exists non_spidered_hosts " );
    $db->query(
"CREATE TABLE non_spidered_hosts ( non_spidered_hosts_id serial primary key, host text unique, linked_to_count integer default 0);"
    );

    $db->query( "DROP TABLE if exists non_blog_host_links; " );
    $db->query(
        "CREATE TABLE non_blog_host_links ( non_blog_host_links_id  serial primary key, url text, site text, host text); " );
    $db->query( "CREATE INDEX non_blog_host_links_url  on non_blog_host_links(url)" );
    $db->query( "CREATE INDEX non_blog_host_links_site on non_blog_host_links(site)" );

    $db->query( "DROP TABLE if exists found_blogs" );
    $db->query(
        "CREATE TABLE found_blogs ( found_blogs_id  serial primary key, site text, url text, title text, rss text); " );
    $db->query( "CREATE INDEX found_blogs_url on found_blogs(url);" );
    $db->query( "CREATE INDEX found_blogs_site on found_blogs(site);" );

    $db->query( "DROP TABLE if exists rejected_blogs" );
    $db->query(
"CREATE TABLE rejected_blogs ( rejected_blogs_id  serial primary key, site text, url text, title text, reason text); "
    );
    $db->query( "CREATE INDEX rejected_blogs_url on rejected_blogs(url);" );
    $db->query( "CREATE INDEX rejected_blogs_site on rejected_blogs(site);" );

    $db->query( "DROP TABLE if exists url_discovery_counts" );
    $db->query( "CREATE TABLE url_discovery_counts " .
          "( url_discovery_status url_discovery_status_type PRIMARY KEY, num_urls INT DEFAULT  0);" );
    $db->query( "INSERT  into url_discovery_counts VALUES ('already_processed') " );
    $db->query( "INSERT  into url_discovery_counts VALUES ('not_yet_processed') " );

    #eval { $db->query("ALTER table downloads drop constraint downloads_story;") };

    for my $spider_url ( @_spider_urls )
    {
        $db->create(
            'downloads',
            {
                url  => $spider_url,
                host => lc( ( URI::Split::uri_split( $spider_url ) )[ 1 ] ),

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
}

main();
