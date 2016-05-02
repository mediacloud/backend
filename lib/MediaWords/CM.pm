package MediaWords::CM;

# General controversy mapper utilities

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;
use Data::Dumper;

# get a list controversies that match the controversy option, which can either be an id
# or a pattern that matches controversy names. Die if no controversies are found.
sub require_controversies_by_opt
{
    my ( $db, $controversy_opt ) = @_;

    if ( !defined( $controversy_opt ) )
    {
        Getopt::Long::GetOptions( "controversy=s" => \$controversy_opt ) || return;
    }

    die( "Usage: $0 --controversy < id or pattern >" ) unless ( $controversy_opt );

    my $controversies;
    if ( $controversy_opt =~ /^\d+$/ )
    {
        $controversies = $db->query( "select * from controversies where controversies_id = ?", $controversy_opt )->hashes;
        die( "No controversies found by id '$controversy_opt'" ) unless ( @{ $controversies } );
    }
    else
    {
        $controversies = $db->query( "select * from controversies where name ~* ?", '^' . $controversy_opt . '$' )->hashes;
        die( "No controversies found by pattern '$controversy_opt'" ) unless ( @{ $controversies } );
    }

    return $controversies;
}

sub get_latest_overall_time_slice
{
    my ( $db, $controversies_id ) = @_;

    my $cdts = $db->query( <<SQL, $controversies_id )->hash;
select *
   from controversy_dump_time_slices cdts
       join controversy_dumps cd on ( cd.controversy_dumps_id = cdts.controversy_dumps_id )
   where
       cd.controversies_id = \$1 and
       cdts.period = 'overall'
   order by cd.dump_date desc
SQL

    return $cdts;
}

sub _get_overall_time_slice_from_snapshot
{
    my ( $db, $snapshot ) = @_;

    my $cdts = $db->query( <<SQL, $snapshot )->hash;
select *
  from controversy_dump_time_slices cdts
  where
    cdts.controversy_dumps_id = \$1 and
    cdts.period = 'overall'
SQL

    LOGDIE( "no overall time slice for snapshot $snapshot" );
}

sub _get_latest_overall_time_slice_from_controversy
{
    my ( $db, $controversies_id ) = @_;
    my $cdts = $db->query( <<SQL, $controversies_id )->hash;
select *
  from controversy_dump_time_slices cdts
  join controversy_dumps cd on (cd.controversy_dumps_id = cdts.controversy_dumps_id)
  where
    cd.controversies_id = \$1 and
    cdts.period = 'overall'
  order by cd.dump_date desc limit 1
SQL
}

# return in order of preference:
# * timeslice if timeslice specified
# * latest timeslice of snapshot is specified
# * latest overall timeslice
sub get_time_slice_for_controversy
{
    my ( $db, $controversies_id, $timeslice, $snapshot ) = @_;

    my $cdts = $db->find_by_id( 'controversy_dump_time_slices', $timeslice );

    return $cdts if ( $cdts );

    $cdts = _get_overall_time_slice_from_snapshot( $db, $snapshot );

    return $cdts if ( $cdts );

    return _get_latest_overall_time_slice_from_controversy( $db, $controversies_id );

    return $cdts;
}

1;
