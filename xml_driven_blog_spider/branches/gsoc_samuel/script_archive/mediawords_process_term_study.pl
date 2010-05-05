#!/usr/bin/perl

# text extraction taking feed id, date, tag name

use strict;
use LWP::UserAgent;
use Data::Dumper;
use XML::TreePP;

BEGIN {
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Crawler::Parser::String;

use Time::Local;
use HTML::Strip;
use Date::Calc::Object;
use lib '/usr/lib/perl5/Date/Calc';
use Date::Manip;

use Encode;

use constant NUMBER_OF_STORIES => 100;
use constant DEFAULT_TAG_SET_NAME => 'term_study';

sub main {

    my $db = MediaWords::DB::authenticate();

    my $full_text;

    my $count = 0;
    my $success = 0;
    my $failure = 0;
    my $stop = 0;

    # COMMAND LINE EXAMPLE:  mediawords_process_term_study.pl 391 20080501 washington_post
    # @ARGV[0] = 391, @ARGV[1] = 20080501, @ARGV[2] = washington_post
    my ($feeds_id, $time_input, $tag_name = @ARGV;

    my $tag_set = $db->resultset('TagSets')
        ->find_or_create( { name => DEFAULT_TAG_SET_NAME } );

    # remove the term_study:<tag_name> tag from all stories
    my @stms = $db->resultset('StoriesTagsMap')
        ->search( { 'tags_id.tag' => $tag_name,
                    'tags_id.tag_sets_id' => $tag_set->tag_sets_id },
                  { join => 'tags_id' } );
    map { $_->delete } @stms;

    # parse the date into the perl time-since-the-epoch format using Time::Local
    $time_input =~ /(^\d\d\d\d)(\d\d)(\d\d)/;
    my $year = $1;
    my $mon = $2;
    my $mday = $3;
    my $hour = '00';
    my $min = '00';
    my $sec = '00';
    my $time_since_the_epoch = timelocal($sec,$min,$hour,$mday,$mon,$year);
    my $time_formatted = $year . "-" . $mon . "-" . $mday . " " . $hour . ":" . $min . ":" . $sec;
    
    my $dateplus2week = Date::Calc::Object->new($year,$mon,$mday) + [0,0,14];

    # lookup all the stories from the given feed published on or after the given date in chronological order.
    my $feed = $db->resultset('Feeds')->find($feeds_id);
    my @stories_rs = $db->resultset('Stories')
        ->search( { 'feeds_stories_maps.feeds_id' => $feeds_id, 
        -and => [ publish_date => { '>=', $time_formatted }, 
                  publish_date => { '<', $dateplus2week } 
                ], 
                },
                  { order_by => 'random()', join => 'feeds_stories_maps' } );

    # for each story until you have extracted 100 stories:
    foreach my $story (@stories_rs) {

        my $encoded_text = "";
        my $numdownloads = 0;
		my $aggregate_story_text = "";
		
        # delete any StoryTexts associated with the story
        if ($story->get_column('story_texts_id') != "") {
            my $found_story_texts_rs = $db->resultset('StoryTexts')
                ->search( { 'story_texts_id' => $story->get_column('story_texts_id') } ,
                          { join => 'story' } );
            if ($found_story_texts_rs) {
                $found_story_texts_rs->delete();
            }
        }



        # find every download associated with that story (some stories will have multiple pages of downloads)
        my @downloads_rs = $db->resultset('Downloads')
            ->search( { 'stories_id' => $story->get_column('stories_id') } ,
                      { order_by => 'parent asc'} );

        # for each download:
        foreach my $download (@downloads_rs) {

            # fetch the content using MediaWords::DB::Downloads->fetch_content()
            my $content_ref = $download->fetch_content();

            if (defined($content_ref)) {

                my $content = $$content_ref;

                # extract the story text using one of the four parsers you've built
                my $extracted_content;

                # NOTE:  media_id=2 means Washington Post, media_id=26 means Sacramento Bee, media_id=115 means Daily Kos, media_id=128 means Red State

                if ($story->get_column('media_id') == 2) {
                    if ($content =~ /\<\!-- Comment Page -->.*Links to this [a-z]+(.*)\<\!-- sphereit end/ms) {
                        $extracted_content = $1;
                    } elsif ($content =~ /\<\!-- Comment Page -->(.*)\<\!-- sphereit end/ms) {
                        $extracted_content = $1;
                    }

                    if (!$extracted_content) {
                        $extracted_content = MediaWords::Crawler::Parser::String->get_story_text("",$content,"article_body","story-navigation-vertical-wrapper");
                    }
                
                    if ($extracted_content eq '') {
                        $extracted_content = MediaWords::Crawler::Parser::String->get_story_text("",$content,"content","commentText");
                        $extracted_content = MediaWords::Crawler::Parser::String->get_story_text("",$extracted_content,"content","posted");
                    }
                    if ($extracted_content eq '') {
                        $extracted_content = MediaWords::Crawler::Parser::String->get_story_text("",$content,"storyText","");
                    }
                } elsif ($story->get_column('media_id') == 26) {
                    $extracted_content = MediaWords::Crawler::Parser::String->get_story_text("",$content,"storyBody","thickbox");
                    $extracted_content = MediaWords::Crawler::Parser::String->get_story_text("",$extracted_content,"storyBody","simg");
                } elsif ($story->get_column('media_id') == 115) {
                    $extracted_content = MediaWords::Crawler::Parser::String->get_story_text("",$content,"story","");
                } elsif ($story->get_column('media_id') == 128) {
                    $extracted_content = MediaWords::Crawler::Parser::String->get_story_text("",$content,"post-body","");
                    if ($extracted_content eq '') {
                        $extracted_content = MediaWords::Crawler::Parser::String->get_story_text("",$content,"secondarystory","h4");
                    }
                } else {
                    die("could not extract content");
                }
            
                #print "Download: " . $download->url . "\n";
                #print "Content:\n****\n$content\n****\n";
                #print "Extracted:\n****\n$extracted_content\n****\n";
            
                # replace newline-generating html entities with newlines
                $extracted_content =~ s/\<p\>/\n/gi;
                $extracted_content =~ s/\<br\>/\n/gi;
                $extracted_content =~ s/\<\/p\>/\n/gi;
                $extracted_content =~ s/\<\/br\>/\n/gi;
            
                # but not an excessive number of newlines
                $extracted_content =~ s/(\n\n)(\n)*/$1/gi;

                # strip the html from the text extract using HTML::Strip
                my $hs = HTML::Strip->new();
                my $stripped_text = $hs->parse($extracted_content);
                $hs->eof;

                # append the resulting text to a aggregate_story_text variable for this story
                $aggregate_story_text .= $stripped_text;            
            
                $numdownloads++;

            }

        }

	$encoded_text = encode('utf-8', $aggregate_story_text);
	$full_text = $encoded_text;

        # if you were able to extract some text:
        if ($encoded_text ne "") {

            # create a new StoryTexts object associated with the story and with the aggregate_story_text as its story_text field
            my $new_story_texts = $db->resultset('StoryTexts')->create({ 
                story_text => $encoded_text,
            });

            $story->story_texts_id($new_story_texts->story_texts_id);
            $story->update;

            # increment number of extracted stories to 100
            $count += 1;

            # add 'term_study:<tag_name>' tag to story
            my $added_tag = $db->resultset('Tags')->find_or_create({
                tag => $tag_name,
                tag_sets_id => $tag_set->tag_sets_id,
            });
            my $stm = $db->resultset('StoriesTagsMap')->create({
                tags_id => $added_tag->tags_id,
                stories_id => $story->stories_id,
            });

                print("Tag: " . $tag_name . "\n");
                print("Tag ID: " . $added_tag->tags_id . "\n");
                print("To access:  Your site should look like \".../stories/tag/" . $added_tag->tags_id . "\"\n");
                print "Stories id: " . $story->stories_id . "\n";
                print "# downloads in this story: $numdownloads\n";
                print("Success: " . $count . "\n");
                print("Failed: " . $failure . "\n");

                if ($count >= NUMBER_OF_STORIES) {
                    last;
                }

        # else:
        } else {

            # print an error message including the url of the story
            print("ERROR:\n Not extracted: Stories ID: " . $story->stories_id . "\n" . $story->url . " !!!\n");

            $failure++;

        }
    }
}

main();

