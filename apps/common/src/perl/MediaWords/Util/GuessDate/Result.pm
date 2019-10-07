package MediaWords::Util::GuessDate::Result;

use strict;
use warnings;

use Readonly;

# Date was found (page was dated)
Readonly our $FOUND => 'found';

# Date was not found on the page or the page is undateable
Readonly our $NOT_FOUND => 'not found';

sub new
{
    my $class = shift;
    my $self  = {};
    bless $self, $class;

    # Date guessing status ($FOUND OR $NOT_FOUND)
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
