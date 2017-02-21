#!/usr/bin/env perl

# given a csv of urls labeled by topic, import each url into the
# topic_seed_urls table.
#
# usage: mediawords_import_topic_seed_urls.pl --file < csv file >
#    [ --topic < topic id or name > ] [ --source < source description > ]
#
# the csv must include these columns:
# * url
#
# the csv must include these columns unless a default is specified on the command line:
# * topic
# * source (text description of the source of the urls)
#
# the csv may include these columns, which will be directlly imported into the resulting story for each url:
# * content
# * publish_date
# * title
# * guid
# * assume_match - 1 or 0, should the topic spider assume that the url matches the topic?

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Data::Dumper;
use Getopt::Long;

use MediaWords::DB;
use MediaWords::Util::CSV;

# find the topic with the given topics_id as either an id or a name.
# die if no topic is found.
sub get_topic
{
    my ( $db, $csv_url, $default_topic ) = @_;

    return $default_topic if ( $default_topic );

    my $topics_id = $csv_url->{ topic };

    die( "no topic specified for url '$csv_url->{ url }'" ) unless ( $default_topic || $topics_id );

    if ( $topics_id =~ /^\d+$/ )
    {
        return $db->find_by_id( 'topics', $topics_id );
    }
    elsif ( $topics_id )
    {
        return $db->query( "select * from topics where name = ?", $topics_id )->hash;
    }

    if ( $topics_id )
    {
        die( "unable to find topic '$topics_id'" ) if ( $topics_id );
    }

    return $default_topic;
}

# store the given seed url in the database if it does not already exist
sub import_seed_url
{
    my ( $db, $default_topic, $default_source, $csv_url ) = @_;

    TRACE "$csv_url->{ url }...";

    $csv_url->{ assume_match } ||= 0;

    $csv_url->{ source } ||= $default_source;
    die( "No source for url '$csv_url->{ url }'" ) unless ( $csv_url->{ source } );

    my $topic = get_topic( $db, $csv_url, $default_topic );

    my $existing_seed_url = $db->query( <<END, $csv_url->{ url }, $topic->{ topics_id } )->hash;
select * from topic_seed_urls where url = ? and topics_id = ?
END

    if ( $existing_seed_url )
    {
        if ( $existing_seed_url->{ assume_match } != $csv_url->{ assume_match } )
        {
            $db->query(
                <<END, normalize_boolean_for_db( $csv_url->{ assume_match } ), $existing_seed_url->{ topic_seed_urls_id } );
update topic_seed_urls set assume_match = ? where topic_seed_urls_id = ?
END
        }

        return;
    }

    my $topic_seed_url = {
        url          => $csv_url->{ url },
        topics_id    => $topic->{ topics_id },
        source       => $csv_url->{ source },
        assume_match => normalize_boolean_for_db( $csv_url->{ assume_match } ),
        content      => $csv_url->{ content },
        publish_date => $csv_url->{ publish_date },
        guid         => $csv_url->{ guid },
        title        => $csv_url->{ title }
    };

    $db->create( 'topic_seed_urls', $topic_seed_url );
}

sub main
{
    my ( $topics_id, $file, $source );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Getopt::Long::GetOptions(
        "topic=s"  => \$topics_id,
        "file=s"   => \$file,
        "source=s" => \$source
    ) || return;

    die( "usage: $0 --file < csv file > [ --topic < topic id or name > ] [ --source < source description > ]" )
      unless ( $file );

    my $db = MediaWords::DB::connect_to_db;

    my $default_topic;
    if ( $topics_id )
    {
        $default_topic = get_topic( $db, { topic => $topics_id, url => 'default' } );
    }

    my $seed_urls = MediaWords::Util::CSV::get_csv_as_hashes( $file );

    $db->begin;

    map { import_seed_url( $db, $default_topic, $source, $_ ) } @{ $seed_urls };

    $db->commit;

}

main();
