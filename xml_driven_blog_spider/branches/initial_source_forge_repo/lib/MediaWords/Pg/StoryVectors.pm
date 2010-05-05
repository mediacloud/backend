package MediaWords::Pg::StoryVectors;

# update the story vectors of any download texts that have been extracted since they were last vectored 
# for now, do this for a single media_id while we catch up with the archive

use strict;

use DBIx::Simple;
use Encode;
use File::Temp;
use HTML::Strip;
use List::Util;
use Lingua::Stem::En;
use Math::Combinatorics;
use Search::FreeText::LexicalAnalysis::Tokenize;

use MediaWords::Pg;
use MediaWords::Util::StopWords;

# number of words in each phrase.  must be at least 2.
use constant PHRASE_WORDS => 5;

# size of window in which to look for a phrase
use constant PHRASE_WINDOW => 6;

# only include phrases that include words from calais tags
use constant REQUIRE_TAG_WORDS_IN_PHRASES => 1;

# minimum length of words in story_phrases
use constant MIN_PHRASE_WORD_LENGTH => 4;

# minimum length of words in story_words
use constant MIN_WORD_LENGTH => 3;

# get the tsvector for the stor and parse it into a list of words sorted by position
sub _get_vector_words {
    my ($stories_id) = @_;
    
    my $tsvector_string = exec_prepared("select vector from story_vectors where stories_id = \$1", 
                                        [ 'INT' ], [ $stories_id ])->{rows}->[0]->{vector};
                                        
    my $tsvector = [];
    while ($tsvector_string =~ /\'([^\']+)\':([0-9,]+)/g) {
        my ($word, $positions_string) = ($1, $2);
        
        if ((length($word) >= MIN_PHRASE_WORD_LENGTH) && ($word !~ /[^[:print:]]/)) {
            for my $p (split(',', $positions_string)) {
                $tsvector->[$p] = $word;
            }
        }
    }

    if (my @sorted_words = grep { $_ } @{$tsvector}) {
        return \@sorted_words;
    } else {
        return [];
    }
}

# return a lookup table of all the words in the calais tags for the story as { word1 => 1, word2 => 1, ...}
# after running the calais tag words through the postgres tsvector normalization
sub _get_calais_tag_word_lookup {
    my ($stories_id) = @_;
    
    my $sth = query_prepared("select to_tsvector(t.tag) as tag_vector from tags t, tag_sets ts, stories_tags_map stm " .
                             "where t.tag_sets_id = ts.tag_sets_id and ts.name = \$1 and " .
                             "stm.tags_id = t.tags_id and stm.stories_id = \$2",
                             [ 'TEXT', 'INT' ],
                             [ 'Calais', $stories_id ]);
    
    my $word_lookup;
    while (my $tag = fetchrow($sth)) {
        while ($tag->{tag_vector} =~ /\'([^\']+)\':([0-9,]+)/g) {
            $word_lookup->{$1} = 1;
        }
    }
    
    cursor_close($sth);
    
    return $word_lookup;
}

# create a set of phrases for the story based on the postgres tsvector
# a phrase is a combination of PHRASE_WORDS unique words within PHRASE_WIDTH of each other within the text
sub _update_story_phrases_old {
    my ($stories_id) = @_;
    
    exec_prepared("delete from story_phrases where stories_id = \$1", [ 'INT' ], [ $stories_id ]);

    my $words = _get_vector_words($stories_id);

    my $num_words = scalar(@{$words});
    
    my $calais_tag_word_lookup = _get_calais_tag_word_lookup($stories_id);
    
    my $story_phrase_vector;
    for (my $beg = 0; $beg < ($num_words - PHRASE_WORDS); $beg++) {
        my $end = List::Util::min($beg + PHRASE_WINDOW, $num_words) - 1;
        
        my $first_word = encode('utf8', $words->[$beg]);

        my $phrase_words;
        my $uniq = { $first_word => 1 };
        # must make list unique, otherwise phrase might be somthing like 'obama obama pass stimulus'.
        for (my $pos = $beg + 1; $pos <= $end; $pos++) {
            if ( !$uniq->{ $words->[$pos] }++ ) {
                push(@{$phrase_words}, encode('utf8', $words->[$pos]));
            }
        }
                
        # only combine everything after the first word because we don't want to repeat any combinations
        # through different runs of the for() loop
        my @phrases = Math::Combinatorics::combine(PHRASE_WORDS - 1, @{$phrase_words});
        
        for my $phrase (@phrases) {
            # only add phrases that include a word from one of the calais tags
            if (!REQUIRE_TAG_WORDS_IN_PHRASES || grep { $calais_tag_word_lookup->{ $_ } } ( $first_word, @{$phrase} )) {
                my $phrase_string = join(" ", sort ( $first_word, @{$phrase} ));
                $story_phrase_vector->{$phrase_string}++;
            }            
        }
    }
    
    #pg_log("inserting " . scalar(keys(%{$story_phrase_vector})) . " phrases");

    my $fh = File::Temp->new( UNLINK => 0 );
    
    while (my ($phrase, $count) = each (%{$story_phrase_vector})) {
        $fh->print($stories_id, "\t", $count, "\t", $phrase, "\n");
    }
    
    $fh->close();
    
    exec_query("copy story_phrases (stories_id, term_count, term) from '" . $fh->filename . "'");
    
    unlink($fh->filename);
}

# create a set of phrases for the story based on the postgres tsvector
# a phrase is a combination of PHRASE_WORDS unique words within PHRASE_WIDTH of each other within the text
sub _update_story_phrases {
    my ($stories_id) = @_;
    
    # drop story phrases for now since they don't work
    return;

    exec_prepared("delete from story_phrases where stories_id = \$1", [ 'INT' ], [ $stories_id ]);

    my $all_words = _get_vector_words($stories_id);

    my $stop_stems = MediaWords::Util::StopWords::get_long_stop_stem_lookup();

    my @stopped_words = grep { !$stop_stems->{$_} } @{$all_words};
    
    my $words = \@stopped_words;
    
    my $num_words = scalar(@{$words});
    
    my $story_phrase_vector;
    for (my $beg = 0; $beg < ($num_words - PHRASE_WORDS); $beg++) {
        my $end = List::Util::min($beg + PHRASE_WINDOW, $num_words) - 1;
        
        my $first_word = encode('utf8', $words->[$beg]);

        my $phrase_words;
        my $uniq = { $first_word => 1 };
        # must make list unique, otherwise phrase might be somthing like 'obama obama pass stimulus'.
        for (my $pos = $beg + 1; $pos <= $end; $pos++) {
            if ( !$uniq->{ $words->[$pos] }++ ) {
                push(@{$phrase_words}, encode('utf8', $words->[$pos]));
            }
        }
                
        # only combine everything after the first word because we don't want to repeat any combinations
        # through different runs of the for() loop
        my @phrases = Math::Combinatorics::combine(PHRASE_WORDS - 1, @{$phrase_words});
        
        for my $phrase (@phrases) {
            # only add phrases that include a word from one of the calais tags
            #if (!REQUIRE_TAG_WORDS_IN_PHRASES || grep { $calais_tag_word_lookup->{ $_ } } ( $first_word, @{$phrase} )) {
                my $phrase_string = join(" ", sort ( $first_word, @{$phrase} ));
                $story_phrase_vector->{$phrase_string}++;
            #}            
        }
    }
    
    #pg_log("inserting " . scalar(keys(%{$story_phrase_vector})) . " phrases");

    my $fh = File::Temp->new( UNLINK => 0 );
    
    while (my ($phrase, $count) = each (%{$story_phrase_vector})) {
        $fh->print($stories_id, "\t", $count, "\t", $phrase, "\n");
    }
    
    $fh->close();
    
    exec_query("copy story_phrases (stories_id, term_count, term) from '" . $fh->filename . "'");
    
    unlink($fh->filename);
}

# get the text for the given story from title, description
sub _get_story_text {
    my ($stories_id) = @_;
    
    my $story = exec_prepared("select * from stories where stories_id = \$1", 
                              [ 'INT' ], [ $stories_id ])->{rows}->[0];
	    
	my $download_texts = exec_prepared("select dt.download_text from download_texts dt, downloads d " .
                                       "where dt.downloads_id = d.downloads_id and d.stories_id = \$1", 
                                       [ 'INT' ], [ $stories_id ])->{rows};
		
	my $hs = HTML::Strip->new();
    my $stripped_title = encode( 'utf8', $hs->parse( $story->{title} || '' ) );
    my $stripped_description = encode( 'utf8', $hs->parse( $story->{description} || '' ) );
    $hs->eof;

    return join (" | ", $stripped_title, $stripped_description, map { $_->{download_text} } @{$download_texts});    
}

# update the story_vector for the given story
sub _update_story_vector {
    my ($stories_id) = @_;
    
    exec_prepared("delete from story_vectors where stories_id = \$1", [ 'INT' ], [ $stories_id ]);

    my $story_text = _get_story_text($stories_id);

    exec_prepared("insert into story_vectors (stories_id, vector) values(\$1, to_tsvector('english', \$2))",
                  [ 'INT', 'TEXT' ], [ $stories_id, $story_text ]);
                  
    return $story_text;
}

# update story_words from the story
sub _update_story_words_old {
    my ($stories_id) = @_;
    
    exec_prepared("delete from story_words where stories_id = \$1", [ 'INT' ], [ $stories_id ]);

    # exec_query('insert into story_words (stories_id, term_count, term) ' . 
    #               'select ' . $stories_id . ', nentry, word ' . 
    #               'from ts_stat(\'select vector from story_vectors where stories_id = ' . $stories_id . '\') q ' .
    #               'where length(word) > ' . MIN_WORD_LENGTH . ' and word ~ \'[a-z]\' and ' .
    #               'not exists (select 1 from stop_words where stop_words.vector = to_tsvector(q.word))');
    my $sth = query('select nentry, word ' . 
                    'from ts_stat(\'select vector from story_vectors where stories_id = ' . $stories_id . '\') q ' .
                    'where length(word) > ' . MIN_WORD_LENGTH . ' and ' . 
                    'word ~ \'[a-z]\' and not word ~ \'[^[:print:]]\'');

    my $stop_stems = MediaWords::Util::StopWords::get_long_stop_stem_lookup();

    my $fh = File::Temp->new( UNLINK => 0 );
        
    while (my $story = fetchrow($sth)) {
        if (!$stop_stems->{$story->{word}}) {
            $fh->print($stories_id, "\t", $story->{nentry}, "\t", encode('utf8', $story->{word}), "\n");
        }
    }
    
    $fh->close();
    
    exec_query("copy story_words (stories_id, term_count, term) from '" . $fh->filename . "'");
    
    unlink($fh->filename);

}

# update story_words from the story
sub _update_story_words {
    my ($stories_id, $story_text) = @_;
    
    exec_prepared("delete from story_words where stories_id = \$1", [ 'INT' ], [ $stories_id ]);

    my $stop_stems = MediaWords::Util::StopWords::get_long_stop_stem_lookup();
    
    my $tokenizer = new Search::FreeText::LexicalAnalysis::Tokenize();
    my $words = $tokenizer->process([ $story_text ]);
    
    Lingua::Stem::En::stem_caching({ -level => 1 });
    my $stems = Lingua::Stem::En::stem({ -words => $words,
                                         -locale => 'en' });                                              

    my $word_counts = {};
    for (my $i = 0; $i < @{$stems}; $i++) {
        if ( $stems->[$i] && 
            ( length($stems->[$i]) >= MIN_WORD_LENGTH ) && 
            ( !$stop_stems->{ $stems->[$i] } ) && 
            ( $stems->[$i] !~ /[^[:print:]]/) ) {
            if (my $wc = $word_counts->{ $stems->[$i] }) {
                $wc->{count}++;
            } else {
                $word_counts->{ $stems->[$i] } = { count => 1, word => $words->[$i] };
            }
        }
    }

    my $fh = File::Temp->new( UNLINK => 0 );
    
    while (my ($stem, $hash) = each(%{$word_counts})) {
        $fh->print($stories_id, "\t", $hash->{count}, "\t", 
                   encode('utf8', $stem), "\t", encode('utf8', lc($hash->{word})), "\n");
    }
    
    $fh->close();
    
    exec_query("copy story_words (stories_id, stem_count, stem, term) from '" . $fh->filename . "'");
    
    unlink($fh->filename);

}

# update the story_vectors, story_words, and story_phrases for all stories in the medium
sub _update_story {
    my ($stories_id) = @_;
    
    my $story_text = _update_story_vector($stories_id);	

    #_update_story_phrases($stories_id);
    
    _update_story_words($stories_id, $story_text);
}

# update the story_vectors and story_phrases tables for all stories within a media source
sub update_media_source_story_vectors {
    my ($media_id) = @_;
    
    eval { 
        my $sth = query_prepared("select stories_id from stories where media_id = \$1", 
                                 [ 'INT' ], [ $media_id ]);

        my $count = 0;
        while (my $story_pending = fetchrow($sth)) {        
            if ((++$count % 100) == 0) {
        	    pg_log("story $media_id-" . $count  . ": " . $story_pending->{stories_id});
    	    }
            _update_story($story_pending->{stories_id});
    	}

    	cursor_close($sth);
    };
    
    if ($@) {
        return "aborted: $@";
    } else {
        return "done";
    }
}

# add a story vector for every story corresponding to a new download_text.
# this should only be run once we catch up and are only handling the last day (or so) of
# entries, or else it will take a very long time to generate the stories_id list.
sub update_pending_story_vectors { 
    
    my $story;
    
    eval {

        my $sth = query("select stories_id, min(dt.download_texts_id) as dt_id " . 
                        "from downloads d, download_texts dt " .
                        "where d.downloads_id = dt.downloads_id and " .
                        "dt.download_texts_id > (select max(download_texts_id) from story_vector_max_dt) " .
                        "group by dt.download_texts_id " .
                        "order by dt.download_texts_id limit 100000");
                        
        my $count = 0;
        while ($story = fetchrow($sth)) {        
        	pg_log("story " . ++$count  . ": " . $story->{stories_id});
            _update_story($story->{stories_id});
        }
        cursor_close($sth);
                
    };
    
    # store the max download texts id so we'll know where to start next time.
    # do this outside the eval so the max dt is stored even if the function
    # is interrupted with ctl-c
    if ($story) {
        exec_query("truncate table story_vector_max_dt");
        exec_query("insert into story_vector_max_dt values(" . $story->{dt_id} . ")");
    }

    if ($@) {
        return "aborted: $@";
    } else {
        return "done";
    }
}

# update story_vectors for any stories_id not present in story vectors.
# this should be used instead of update_pending_story_vectors to initially load
# the story_vectors because it will run much quicker.  It should not used for the
# daily load once we are caught up, though, because it does not detect udpated
# download_texts for stories that already have a story_vector.
# this will only handle up to 500k rows each run, since postgres does not allow 
# committing a server side function, so it needs to be run in a loop to handle all stories
sub update_all_missing_story_vectors {
    
    eval {
        
        # specifically exclude anything from the last week so that we don't
        # include a story that has not yet been extracted
        my $sth = query("select s.stories_id from stories s left join story_vectors sv on s.stories_id = sv.stories_id " .
                        "where s.publish_date < (now() - interval '1 week') and sv.stories_id is null");
            
        my $count = 0;            
        while (my $story = fetchrow($sth)) {
        	pg_log("story " . ++$count  . ": " . $story->{stories_id});
            _update_story($story->{stories_id});            
        }
        cursor_close($sth);
    
    };
    
    if ($@) {
        return "aborted: $@";
    } else {
        return "done";
    }
}

# this is a temporary fix to keep just the word_cloud:* media up to date
sub update_wordcloud_story_vectors {
    
    eval {
        
        my $sth = query("select s.stories_id from stories s, media_tags_map mtm, tags t, tag_sets ts " .
                        "  where s.media_id = mtm.media_id and mtm.tags_id = t.tags_id and t.tag_sets_id = ts.tag_sets_id " .
                        "    and ts.name = 'word_cloud' and s.publish_date > now() - interval '30 days' " .
                        "    and not exists (select 1 from story_vectors sv where sv.stories_id = s.stories_id)");
        
        my $count = 0;            
        while (my $story = fetchrow($sth)) {
            my $downloads_not_extracted = exec_prepared("select downloads_id from downloads " . 
                                                        "  where extracted = 'f' and type = 'content' and state = 'success' " . 
                                                        "    and stories_id = \$1", [ 'INT' ], [ $story->{stories_id} ] )->{rows};
            if (@{$downloads_not_extracted}) {
                next;
            }
            
        	pg_log("story " . ++$count  . ": " . $story->{stories_id});
            _update_story($story->{stories_id});            
        }
        cursor_close($sth);
    
    };
    
    if ($@) {
        return "aborted: $@";
    } else {
        return "done";
    }
}

# fill the story_words table with all words in story_vectors
sub fill_story_words {
    
    my $count = 0;

    exec_query("truncate table story_words");

    my $sth = query("select stories_id from story_vectors");
    
    while (my $story = fetchrow($sth)) {
        if ((++$count % 100) == 0) {
            pg_log("story $count");
        }

        my $story_text = _get_story_text($story->{stories_id});
        _update_story_words($story->{stories_id}, $story_text);
    }    
    
    cursor_close($sth);
    
    exec_query("analyze story_words");
    
    return 'done';
}

# fill the story_phrases table with all phrases in story_vectors
sub fill_story_phrases {
    
    my $count = 0;

    exec_query("truncate table story_phrases");

    my $sth = query("select stories_id from story_vectors");
    
    while (my $story = fetchrow($sth)) {
        if ((++$count % 100) == 0) {
            pg_log("story $count");
        }

        _update_story_phrases($story->{stories_id});
    }    
    
    cursor_close($sth);
    
    exec_query("analyze story_phrases");
    
    return 'done';
}

1;