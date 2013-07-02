package MediaWords::CM::GuessDate::Result;

use strict;
use warnings;

use constant {

    # Date was found (page was dated)
    FOUND => 'found',

    # Date was not found on the page
    NOT_FOUND => 'not found',

    # Page should not be dated (responds with 404 Not Found, is a tag page, search page, wiki page, etc.)
    INAPPLICABLE => 'inapplicable',

};

sub new
{
    my $class = shift;
    my $self  = {};
    bless $self, $class;

    # Date guessing status (FOUND, NOT_FOUND or INAPPLICABLE)
    $self->{ result } = undef;

    # Date guessing method used (string), if applicable
    $self->{ guess_method } = undef;

    # Date UNIX timestamp / epoch (integer), if applicable
    $self->{ timestamp } = undef;

    # String date, ISO-8601 string in GMT timezone (e.g. '2012-01-17T17:00:00')
    $self->{ date } = undef;

    return $self;
}

1;
