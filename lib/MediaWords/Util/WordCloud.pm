package MediaWords::Util::WordCloud;

# generate a word cloud based on a query and a list of words

use strict;

use Data::Dumper;
use Switch 'Perl6';

use HTML::TagCloud;
use List::MoreUtils;

# number of words in a word cloud
use constant NUM_WORD_CLOUD_WORDS => 100;

# return the html for a word cloud of the given words.
#
# link each word in the url to /dashboard/sentences for the current query and
# the given term. optionally pass an author in place of a query.
sub get_word_cloud
{
    my ( $c, $base_url, $words, $query ) = @_;

    if ( @{ $words } > NUM_WORD_CLOUD_WORDS )
    {
        $words = [ @{ $words }[ 0 .. (NUM_WORD_CLOUD_WORDS - 1) ] ];
    }

    my $cloud = HTML::TagCloud->new;

    for my $word ( @{ $words } )
    {

        my $url = $c->uri_for( $base_url, { 
            queries_ids => $query->{ queries_id }, authors_id => $query->{ authors_id }, 
            stem => $word->{ stem }, term => $word->{ term } } );

        if ( $word->{ stem_count } == 0 )
        {
            warn "0 stem count for word:" . Dumper( $word );
        }
        else
        {
            $cloud->add( $word->{ term }, $url, $word->{ stem_count } * 100000 );
        }
    }

    $c->keep_flash( ( 'translate' ) );

    my $html = $cloud->html;

    #<span class="tagcloud24"><a onclick="this.style.color='red '; return false;"
    if ( $c->req->param( 'highlight_mode' ) )
    {
        $html =~ s/(span class="tagcloud[0-9]+"><a)/$1 onclick="this.style.color='red '; return false;"/g;
    }

    return $html;
}

sub _get_set_for_word
{
    my ( $words_1_hash, $words_2_hash, $word ) = @_;

    if ( defined( $words_1_hash->{ $word } ) && defined( $words_2_hash->{ $word } ) )
    {
        return "both";
    }
    elsif ( defined( $words_1_hash->{ $word } ) )
    {
        return "list_1";
    }
    else
    {
        die "Neither list contains word '$word'" unless defined( $words_2_hash->{ $word } );
        return "list_2";
    }
}

sub _get_merged_word_count
{
    my ( $words_1_hash, $words_2_hash, $word ) = @_;

    my $set = _get_set_for_word( $words_1_hash, $words_2_hash, $word );

    my $ret;

    given ( $set )
    {

        when 'list_1' { $ret = $words_1_hash->{ $word }; }
        when 'list_2' { $ret = $words_2_hash->{ $word }; }
        when 'both'
        {
            my $temp_hash_ref = $words_1_hash->{ $word };

            #copy hash
            # TODO why is this bad?
            my %temp = ( %$temp_hash_ref );
            $temp{ stem_count } += $words_2_hash->{ $word }->{ stem_count };
            $ret = \%temp;
        }
        default
        {
            die "Invalid case '$set'";

        }
    }

    #TODO copy $ret
    return $ret;
}

# get a word cloud for two different lists of words and queries, coloring
# words that appear in one blue, the other red, and both purple 
sub get_multi_set_word_cloud
{
    my ( $c, $dashboard, $words, $queries ) = @_;

    my $dashboards_id = $dashboard ? $dashboard->{ dashboards_id } : 1;

    splice( @{ $words->[ 0 ] }, NUM_WORD_CLOUD_WORDS ) if ( @{ $words->[ 0 ] } > NUM_WORD_CLOUD_WORDS );
    splice( @{ $words->[ 1 ] }, NUM_WORD_CLOUD_WORDS ) if ( @{ $words->[ 1 ] } > NUM_WORD_CLOUD_WORDS );

    my $cloud = HTML::TagCloud->new;

    my $words_1_hash = { map { $_->{ stem } => $_ } @{ $words->[ 0 ] } };
    my $words_2_hash = { map { $_->{ stem } => $_ } @{ $words->[ 1 ] } };

    die "Word list object should be different" if $words->[ 0 ] == $words->[ 1 ];
    
    my $all_words_hash= { %{ $words_1_hash }, %{ $words_2_hash } };
    my @all_words = keys( %{ $all_words_hash } );

    for my $word ( @all_words )
    {
        my $word_record = _get_merged_word_count( $words_1_hash, $words_2_hash, $word );
        my $set = _get_set_for_word( $words_1_hash, $words_2_hash, $word );

        if ( $word_record->{ stem_count } == 0 )
        {
            warn "0 stem count for word:" . Dumper( $word_record );
        }
        else
        {
            my $queries_ids;            
            given ( $set )
            {
                when 'list_1' { $queries_ids = $queries->[0]->{ queries_id }; }
                when 'list_2' { $queries_ids = $queries->[1]->{ queries_id }; }
                when 'both'   { $queries_ids = [ map { $_->{ queries_id } } @{ $queries } ]; }
            }   

            my $url = $c->uri_for( "/dashboard/sentences/$dashboards_id",
                { queries_ids => $queries_ids, stem => $word_record->{ stem }, term => $word_record->{ term }, set => $set } );
            
            $cloud->add( $word_record->{ term }, $url, $word_record->{ stem_count } * 100000 );
        }
    }

    $c->keep_flash( ( 'translate' ) );

    my $html = $cloud->html;

    #<span class="tagcloud24"><a onclick="this.style.color='red '; return false;"
    $html =~ s/<a href="([^"]*set=list_2[^"]*)">/<a href="$1" class="word_cloud_list2">/g;
    $html =~ s/<a href="([^"]*set=list_1[^"]*)">/<a href="$1" class="word_cloud_list1">/g;
    $html =~ s/<a href="([^"]*set=both[^"]*)">/<a href="$1" class="word_cloud_both_lists">/g;

    if ( $c->req->param( 'highlight_mode' ) )
    {
        $html =~ s/(span class="tagcloud[0-9]+"><a)/$1 onclick="this.style.color='red '; return false;"/g;
    }

    return $html;
}

1;