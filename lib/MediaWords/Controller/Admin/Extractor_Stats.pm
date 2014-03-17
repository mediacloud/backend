package MediaWords::Controller::Admin::Extractor_Stats;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use DateTime;

# MODULES

use HTML::Entities;

use MediaWords::Crawler::Extractor;

# CONSTANTS

use constant ROWS_PER_PAGE => 100;

# METHODS

sub index : Path : Args(0)
{
    return list( @_ );
}

sub list : Local
{
    my ( $self, $c ) = @_;

    my $result = $c->dbis->query(
'select submitter, count(*) from (select distinct on (stories_id) stories_id, submitter from downloads, extractor_training_lines where extractor_training_lines.downloads_id = downloads.downloads_id) as foo group by submitter order by count desc'
    );

    $c->stash->{ extractor_stats } = $result->hashes();

    $c->stash->{ template } = 'extractor_stats/list.tt2';
}

1;
