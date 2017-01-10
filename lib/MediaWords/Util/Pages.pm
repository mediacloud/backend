package MediaWords::Util::Pages;

#
# Utility class for calculating pages (copied from Data::Page, used in include/pager.tt2)
#
# Makes the functionality more portable to Python because it's our own code, not someone else's.
#
# Copyright belongs to http://search.cpan.org/~lbrocard/Data-Page-2.02/ author.
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;

has '_total_entries'    => ( is => 'rw', isa => 'Int' );
has '_entries_per_page' => ( is => 'rw', isa => 'Int' );
has '_current_page'     => ( is => 'rw', isa => 'Int' );

sub new($$$$)
{
    my $class = shift;
    my ( $total_entries, $entries_per_page, $current_page ) = @_;

    unless ( defined $total_entries and defined $entries_per_page and defined $current_page )
    {
        die "new() expects three parameters.";
    }

    if ( $entries_per_page < 1 )
    {
        die "Fewer than one entry per page!";
    }

    my $self = {};
    bless( $self, $class );

    $self->_total_entries( $total_entries );
    $self->_entries_per_page( $entries_per_page );
    $self->_current_page( $current_page );

    return $self;
}

# This method returns the previous page number, if one exists. Otherwise
# it returns undefined:
#
#   if ($page->previous_page) {
#     print "Previous page number: ", $page->previous_page, "\n";
#   }
#
sub previous_page($)
{
    my $self = shift;

    if ( $self->_current_page > 1 )
    {
        return $self->_current_page - 1;
    }
    else
    {
        return undef;
    }
}

# This method returns the next page number, if one exists. Otherwise
# it returns undefined:
#
#   if ($page->next_page) {
#     print "Next page number: ", $page->next_page, "\n";
#   }
#
sub next_page($)
{
    my $self = shift;

    if ( $self->_current_page < $self->_last_page() )
    {
        return $self->_current_page + 1;
    }
    else
    {
        return undef;
    }
}

# This method returns the number of the first entry on the current page:
#
#   print "Showing entries from: ", $page->first, "\n";
#
sub first($)
{
    my $self = shift;

    if ( $self->_total_entries == 0 )
    {
        return 0;
    }
    else
    {
        return ( ( $self->_current_page - 1 ) * $self->_entries_per_page ) + 1;
    }
}

# This method returns the number of the last entry on the current page:
#
#   print "Showing entries to: ", $page->last, "\n";
#
sub last($)
{
    my $self = shift;

    if ( $self->_current_page == $self->_last_page() )
    {
        return $self->_total_entries;
    }
    else
    {
        return ( $self->_current_page * $self->_entries_per_page );
    }
}

# This method returns the total number of pages of information:
#
#   print "Pages range to: ", $page->_last_page(), "\n";
#
sub _last_page
{
    my $self = shift;

    my $pages = $self->_total_entries / $self->_entries_per_page;
    my $last_page;

    if ( $pages == int( $pages ) )
    {
        $last_page = $pages;
    }
    else
    {
        $last_page = int( $pages ) + 1;
    }

    if ( $last_page < 1 )
    {
        $last_page = 1;
    }

    return $last_page;
}

1;
