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
    
    my $params = 
        { 
            base_url => 'http://amanda.law.harvard.edu/admin',
            
            media_sets => 
                [ { name => 'Top 25 Mainstream Media', nickname => 'msm', compare => 1 },
                  { name => 'Political Blogs - Left', nickname => 'left_blogs', compare => 1 },
                  { name => 'Political Blogs - Right', nickname => 'right_blogs', compare => 1 },
                ],                  
            
            media_set_groups => [ { nickname => 'blogs', media_set_nicknames => [ 'left_blogs', 'right_blogs' ], compare => 1 } ],
            
            pole_media_sets => [ { nickname => 'msm' } ],
            
            topic_names => 
                [ 
                  'Economy',
                  'Obama',
                  'Egypt',
                  'deficit',
                  'Tea',
                  'election',
                  'tax',
                  'Libya',
                  'recession',
                  'Inequality',
                  
                ],
            
            topic_dates => {},
                  # 'Seliger (Full)' => [ '2011-06-01', '2011-09-01' ],
            
            default_topic_dates => [ '2010-12-01', '2011-12-01' ],
        };

    print MediaWords::Util::CountryAnalysis::get_results_as_encoded_csv( $db, $params );
}

main();