package MediaWords::Tagger::NYTTopics;
use MediaWords::CommonLibs;

# search through the text for nyt topic terms

use strict;

use MediaWords::Util::Config;

my $_topics;

# get list of topics
sub get_topics_hash
{

    my $data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

    my $nyt_file = "$data_dir/tagger/nyt_topics.txt";
    if ( !open( FILE, $nyt_file ) )
    {
        die( "Unable to open file $nyt_file: $!" );
    }

    my $topics = {};
    map { chomp( $_ ); $topics->{ lc( $_ ) } = 1; } ( <FILE> );

    close( FILE );

    my $nyt_stop_file = "$data_dir/tagger/nyt_topics_stopwords.txt";
    if ( !open( FILE, $nyt_stop_file ) )
    {
        die( "Unable to open file $nyt_stop_file: $!" );
    }

    map { chomp( $_ ); delete( $topics->{ lc( $_ ) } ) } ( <FILE> );

    close( FILE );

    return $topics;
}

# load all topics from nyt into a hash
sub initialize_topics
{

    if ( $_topics )
    {
        return;
    }

    $_topics = get_topics_hash();
}

sub get_tags
{
    my ( $text ) = @_;

    eval { initialize_topics(); };
    if ( $@ )
    {
        return { error => $@ };
    }

    my @words = split( /\W/, $text );

    my $matching_topics = {};
    for ( my $i = 0 ; $i < @words ; $i++ )
    {
        for ( my $j = 0 ; ( ( $i + $j ) < @words ) && ( $j < 3 ) ; $j++ )
        {
            my $word = lc( join( " ", @words[ $i .. ( $i + $j ) ] ) );
            $word =~ s/^\s+//;
            $word =~ s/\s+$//;

            if ( length( $word ) > 3 )
            {

                #print "check word: $word\n";
                if ( $_topics->{ $word } )
                {

                    #print "match\n";
                    $matching_topics->{ lc( $word ) } = 1;
                    $i += $j;
                }
            }
        }
    }

    return { tags => [ sort { $a cmp $b } keys( %{ $matching_topics } ) ] };
}

1;
