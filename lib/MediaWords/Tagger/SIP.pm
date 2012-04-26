package MediaWords::Tagger::SIP;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

#This is just a very quick and dirty first implementation of some of the SIP tagging I had in mind
#At this point, this is only story by story tagging; I haven't yet implemented the sort of daily meme tracking we discussed

#My major TODOs:
#1. Recognize 1-5 word phrases, instead of just individual words
#
#2. Train off articles seen so far, instead of just a small static collection of books from Project Gutenberg
#      The major problem with training off books is that since I tell the SIP finder to ignore words it never saw in training
#      it ignores most names and places. This will work properly once it starts training on articles though.
#
#3. Find SIPs per six hour period (from all sources) instead of just per article
#
#4. Some sort of pretty visulatization for the memes

#Timeline:
#I estimate 1 and 2 combined will be about 10 hours of work (~1 week)
#3 could be a bit bigger, since I'll have to learn more about the existing code, and Catalyst. I estimate about 20 hours (~2 more weeks)
#Finally, #4 should take about another 10 hours (~1 week) to do

#That ideally means I should be done with this stuff by the beginning of November.
#Throw in another 20 hours (2 weeks) for unforseen difficulties and refactoring, and I estimate completion of TODOs 1-4 by mid November

use strict;
use warnings;

use BerkeleyDB;

use MediaWords::Util::Config;

my $filename  = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir } . "/tagger/sip_data.dbm";
my $threshold = 5;
my $max_sip   = 10;

sub get_tags
{
    my ( $content ) = @_;

    my @tags;
    eval {
        my $bdb = new BerkeleyDB::Hash( -Filename => $filename, -Flags => DB_CREATE )
          or die "Cannot open $filename: $!\n";

        my $data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

        if ( get_val( $bdb, "IS_MY_BDB_TRAINED_LONG_KEY" ) == 0 )
        {
            for my $f (
                qw/nyt_current_history.txt sex.txt alice_in_wonderland.txt emma.txt jane_eyre.txt
                pride_and_prejudice.txt thesaurus.txt devils_dictionary.txt frankenstein.txt/
              )
            {
                train_file( $bdb, "$data_dir/tagger/sip-books/$f" );
            }
            $bdb->db_put( "IS_MY_BDB_TRAINED_LONG_KEY", 1 );
        }

        @tags = sip_content( $bdb, $content );
        close $bdb->db_close();
    };

    if ( $@ )
    {
        return { error => $@ };
    }
    else
    {
        return { tags => \@tags };
    }

}

sub get_val
{
    my ( $db_handle, $key ) = @_;
    my $value;

    if ( $db_handle->db_get( $key, $value ) == DB_NOTFOUND )
    {
        return 0;
    }

    return $value;
}

sub incr_val
{
    my ( $db_handle, $key ) = @_;
    my $val = get_val( $db_handle, $key );
    $db_handle->db_put( $key, $val + 1 );
}

sub add_word
{
    my ( $db_handle, $word ) = @_;
    incr_val( $db_handle, lc( $word ) );
    incr_val( $db_handle, "count" );
}

sub get_prob
{
    my ( $db_handle, $word ) = @_;
    return get_val( $db_handle, lc( $word ) ) / get_val( $db_handle, "count" );
}

sub train_file
{
    my ( $db_handle, $file ) = @_;
    open( FILE, "<$file" );
    while ( <FILE> )
    {
        chomp;
        train_content( $db_handle, $_ );
    }
    close FILE;
}

sub seperate_words
{
    my ( $text ) = @_;
    return map { /([\w\-']+)/i }    #strip out puncuation, besides apostraphes and hyphens
      split /\s+/s, $text;
}

sub train_content
{
    my $word;
    my ( $db_handle, $content ) = @_;

    foreach $word ( seperate_words( $content ) )
    {
        add_word( $db_handle, $word );
    }
}

sub sip_file
{
    my ( $db_handle, $file ) = @_;
    open FILE, "<$file";
    my $content = join( " ", <FILE> );
    sip_content( $db_handle, $content );
}

sub sip_content
{
    my ( $db_handle, $content ) = @_;

    my @words       = seperate_words( $content );
    my $total_count = @words;
    my %distribution;
    my $word;
    my $word_count;

    #count the number of times each word appears
    foreach $word ( @words )
    {
        $word_count = $distribution{ $word };
        if ( !$word_count )
        {
            $distribution{ $word } = 1;
        }
        else
        {
            $distribution{ $word } = $word_count + 1;
        }
    }

    #compute the ratio of a word's frequency in this text to its frequency in the training data
    while ( ( $word, $word_count ) = each %distribution )
    {
        if ( get_prob( $db_handle, $word ) > 0 )
        {
            $distribution{ $word } = ( $word_count / $total_count ) / get_prob( $db_handle, $word );
        }
    }

    #sort from most improbable down
    @words = sort { $distribution{ $b } <=> $distribution{ $a } } keys %distribution;

    #return words more improbable than the threshold
    my @res;
    my $count = 0;
    do
    {
        push( @res, shift( @words ) );
        $count++;
    } while ( $distribution{ $res[ -1 ] } >= $threshold && $count < $max_sip );

    return @res;
}

1;
