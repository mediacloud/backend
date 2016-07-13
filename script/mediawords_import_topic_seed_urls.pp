#!/usr/bin/env perl

# given a csv of urls labeled by controversy, import each url into the
# controversy_seed_urls table.
#
# usage: mediawords_import_controversy_seed_urls.pl --file < csv file >
#    [ --controversy < controversy id or name > ] [ --source < source description > ]
#
# the csv must include these columns:
# * url
#
# the csv must include these columns unless a default is specified on the command line:
# * controversy
# * source (text description of the source of the urls)
#
# the csv may include these columns, which will be directlly imported into the resulting story for each url:
# * content
# * publish_date
# * title
# * guid
# * assume_match - 1 or 0, should the controversy spider assume that the url matches the controversy?

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
use MediaWords::Util::CSV;

# find the controversy with the given controversies_id as either an id or a name.
# die if no controversy is found.
sub get_controversy
{
    my ( $db, $csv_url, $default_controversy ) = @_;

    return $default_controversy if ( $default_controversy );

    my $controversies_id = $csv_url->{ controversy };

    die( "no controversy specified for url '$csv_url->{ url }'" ) unless ( $default_controversy || $controversies_id );

    if ( $controversies_id =~ /^\d+$/ )
    {
        return $db->find_by_id( 'controversies', $controversies_id );
    }
    elsif ( $controversies_id )
    {
        return $db->query( "select * from controversies where name = ?", $controversies_id )->hash;
    }

    if ( $controversies_id )
    {
        die( "unable to find controversy '$controversies_id'" ) if ( $controversies_id );
    }

    return $default_controversy;
}

# store the given seed url in the database if it does not already exist
sub import_seed_url
{
    my ( $db, $default_controversy, $default_source, $csv_url ) = @_;

    # print STDERR "$csv_url->{ url }...\n";

    $csv_url->{ assume_match } ||= 0;

    $csv_url->{ source } ||= $default_source;
    die( "No source for url '$csv_url->{ url }'" ) unless ( $csv_url->{ source } );

    my $controversy = get_controversy( $db, $csv_url, $default_controversy );

    my $existing_seed_url = $db->query( <<END, $csv_url->{ url }, $controversy->{ controversies_id } )->hash;
select * from controversy_seed_urls where url = ? and controversies_id = ?
END

    if ( $existing_seed_url )
    {
        if ( $existing_seed_url->{ assume_match } != $csv_url->{ assume_match } )
        {
            $db->query( <<END, $csv_url->{ assume_match }, $existing_seed_url->{ controversy_seed_urls_id } );
update controversy_seed_urls set assume_match = ? where controversy_seed_urls_id = ?
END
        }

        return;
    }

    my $controversy_seed_url = {
        url              => $csv_url->{ url },
        controversies_id => $controversy->{ controversies_id },
        source           => $csv_url->{ source },
        assume_match     => $csv_url->{ assume_match },
        content          => $csv_url->{ content },
        publish_date     => $csv_url->{ publish_date },
        guid             => $csv_url->{ guid },
        title            => $csv_url->{ title }
    };

    $db->create( 'controversy_seed_urls', $controversy_seed_url );
}

sub main
{
    my ( $controversies_id, $file, $source );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Getopt::Long::GetOptions(
        "controversy=s" => \$controversies_id,
        "file=s"        => \$file,
        "source=s"      => \$source
    ) || return;

    die( "usage: $0 --file < csv file > [ --controversy < controversy id or name > ] [ --source < source description > ]" )
      unless ( $file );

    my $db = MediaWords::DB::connect_to_db;

    my $default_controversy;
    if ( $controversies_id )
    {
        $default_controversy = get_controversy( $db, { controversy => $controversies_id, url => 'default' } );
    }

    my $seed_urls = MediaWords::Util::CSV::get_csv_as_hashes( $file );

    $db->begin;

    map { import_seed_url( $db, $default_controversy, $source, $_ ) } @{ $seed_urls };

    $db->commit;

}

main();
