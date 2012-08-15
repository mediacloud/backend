#!/usr/bin/env perl

# generate a csv of urls of query based urls for the russia project.
# the columnns of the table are topics, and the rows are various
# query tool results for each topic

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Util::CountryAnalysis;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $params = {
        base_url => 'http://amanda.law.harvard.edu/admin',

        media_sets => [
            { name => 'Russian Top 25 Mainstream Media', nickname => 'msm',   compare       => 1 },
            { name => 'Russian Government',              nickname => 'gov',   compare       => 1 },
            { name => 'Russian TV',                      nickname => 'tv',    compare       => 1 },
            { name => 'Politics: Ethno-Nationalists',    nickname => 'ethno', media_sets_id => 16712 },
            { name => 'Politics: Democratic Opposition', nickname => 'dem',   media_sets_id => 16715 }
        ],

        media_set_groups => [ { nickname => 'blogs', media_set_nicknames => [ 'ethno', 'dem' ], compare => 1 } ],

        pole_media_sets => [ { nickname => 'gov' }, { nickname => 'msm' } ],

        topic_names => [
            'Protest (miting) (full)',
            'Modernization (Full)',
            'Buckets (Full)',
            'Kashin (Full)',
            'Putin (Full)',
            'Terrorist Act (Full)',
            'Tunisia (Full)',
            'Khimki (Full)',
            'Khodorkovsky (Full)',
            'Domodedovo (Full)',
            'Corruption (Full)',
            'Blue (Full)',
            'anti-seliger (Full)',
            'Kudrin (Full)',
            'Smog (Full)',
            'Riots (Full)',
            'Explosion (Full)',
            'Egypt (Full)',
            'Metro (Full)',
            'Seliger (Full)',
            'Protest (Full)',
            'Skolkovo (Full)',
            'Flashing Lights (Full)',
            'Terroist Act (Full)',
            'Nashi (Full)',
            'Fire (Full)',
            'Medvedev (Full)',
        ],

        topic_dates => {
            'Egypt (Full)'            => [ '2011-01-01', '2011-03-01' ],
            'Seliger (Full)'          => [ '2011-06-01', '2011-09-01' ],
            'anti-seliger (Full)'     => [ '2011-06-01', '2011-09-01' ],
            'Protest (miting) (full)' => [ '2011-12-01', '2012-01-01' ],
            'Protest (Full)'          => [ '2011-12-01', '2012-01-01' ]
        },

        default_topic_dates => [ '2010-12-01', '2011-12-01' ],
    };

    print MediaWords::Util::CountryAnalysis::get_results_as_encoded_csv( $db, $params );
}

main();
