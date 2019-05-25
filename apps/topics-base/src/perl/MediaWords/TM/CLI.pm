package MediaWords::TM::CLI;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;

# get a list topics that match the topic option, which can either be an id
# or a pattern that matches topic names. Die if no topics are found.
sub require_topics_by_opt
{
    my ( $db, $topic_opt ) = @_;

    if ( !defined( $topic_opt ) )
    {
        Getopt::Long::GetOptions( "topic=s" => \$topic_opt ) || return;
    }

    die( "Usage: $0 --topic < id or pattern >" ) unless ( $topic_opt );

    my $topics;
    if ( $topic_opt =~ /^\d+$/ )
    {
        $topics = $db->query( "select * from topics where topics_id = ?", $topic_opt )->hashes;
        die( "No topics found by id '$topic_opt'" ) unless ( @{ $topics } );
    }
    else
    {
        $topics = $db->query( "select * from topics where name ~* ?", '^' . $topic_opt . '$' )->hashes;
        die( "No topics found by pattern '$topic_opt'" ) unless ( @{ $topics } );
    }

    return $topics;
}

1;
