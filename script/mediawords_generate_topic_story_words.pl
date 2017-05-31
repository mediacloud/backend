#!/usr/bin/env perl

# generate dumps of 1000 stories apiece of stories from a topic timespan, with word counts

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::CommonLibs;
use Modern::Perl '2015';

use File::Slurp;

use MediaWords::DB;
use MediaWords::Util::JSON;
use MediaWords::Util::Web;

sub main
{
    my ( $timespans_id ) = @ARGV;

    die( "usage: $0 <timespans_id>" ) unless ( $timespans_id );

    my $db = MediaWords::DB::connect_to_db;

    my ( $key ) = $db->query( <<SQL )->flat;
        SELECT api_key
        FROM auth_roles
            INNER JOIN auth_user_api_keys USING (auth_users_id)
        WHERE auth_roles.role = 'admin'
          AND auth_user_api_keys.ip_address IS NULL
        LIMIT 1
SQL

    my $stories_count = 0;
    my $base_url =
      "https://api.mediacloud.org/api/v2/stories_public/list?key=$key&q=timespans_id:$timespans_id&rows=1000&wc=1";
    my $psid = 0;
    while ( 1 )
    {
        my $url = "$base_url&last_processed_stories_id=$psid.json";
        say STDERR "fetching $url ...";

        my $ua   = MediaWords::Util::Web::UserAgent->new();
        my $json = $ua->get_string( $url );

        die( 'url failed: ' . $url ) unless ( $json );

        write_file( "topic_stories_${ timespans_id }_${ psid }", $json );

        my $data = MediaWords::Util::JSON::decode_json( $json );

        my $psids = [ map { $_->{ processed_stories_id } } @{ $data } ];

        last if ( !@{ $psids } );

        say STDERR "got " . scalar( @{ $psids } ) . " stories";

        $psid = ( sort { $b <=> $a } @{ $psids } )[ 0 ];
        $stories_count += @{ $psids };
    }

    say STDERR "total stories: $stories_count";
}

main();
