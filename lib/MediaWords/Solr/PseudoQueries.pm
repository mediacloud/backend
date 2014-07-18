package MediaWords::Solr::PseudoQueries;

use strict;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

# transform pseudo query clauses in solr queries
#
# pseudo queries allow us to effectively perform joins with postgres
# queries directly through the api with queries that look like:
#
# sentence:obama and {? controversy_dump_time_slice:1234 }
#
# which would be processed and replaced before sending to solr with
# something that looks like:
#
# sentence:obama and stories_id:( ... )
#

use List::Compare;
use Readonly;

use MediaWords::DB;

# list of field functions that can be called within a psuedo query clause.
# the list is in [ $field_name, $field_function, $num_required_args ] format.
# for each such field in a pseudo query in field_name:arg1[-arg2 ...] format,
# the function referenced below is called on the given query, and a hash
# with at least a stories_id key is returned.  The field functions are called
# in the order listed below, and subsequent calls have access to the records
# returned by previous calls, so for example the controversy_link_community
# call has access to the controversy_dump_time_slice return value to determine
# which controversy time slice to mine for link community.
Readonly my $FIELD_FUNCTIONS => [
    [ 'controversy',                 \&_transform_controversy_field,                 1 ],
    [ 'controversy_dump_time_slice', \&_transform_controversy_dump_time_slice_field, 1 ],
    [ 'tag_link',                    \&_transform_tag_link_field,                    1 ],
];

# accept controversy:1234 clause and return a controversy id and a list of
# stories in the live controversy
sub _transform_controversy_field
{
    my ( $db, $return_data, $controversies_id ) = @_;

    my $stories_ids = $db->query( <<END, $controversies_id )->flat;
select stories_id from controversy_stories where controversies_id = ?
END

    return { controversies_id => $controversies_id, stories_ids => $stories_ids };
}

# accept controversy_dump_time_slice:1234 clause and return a cdts id and a list of
# stories_ids
sub _transform_controversy_dump_time_slice_field
{
    my ( $db, $return_data, $cdts_id ) = @_;

    my $stories_ids = $db->query( <<END, $cdts_id )->flat;
select stories_id from cd.story_link_counts where controversy_dump_time_slices_id = ?
END

    return { controversy_dump_time_slices_id => $cdts_id, stories_ids => $stories_ids };
}

# accept tag_link:1234[-5678] clause and return a list of stories_ids where
# the stories are those that from stories tagged with the first tags_id (either directly
# or through media) and optionally link to stories tagged with the second tags_id.  if
# the second tags_id is 'other', return stories link from the first tags_id and linking
# to any story but the given tags_id.
sub _transform_tag_link_field
{
    my ( $db, $return_data, $from_tags_id, $to_tags_id ) = @_;

    die( "pseudo query error: tag_link field requires a controversy_dump_time_slice field in the same pseudo query clause" )
      unless ( $return_data->{ controversy_dump_time_slice } );

    my $cdts_id = $return_data->{ controversy_dump_time_slice }->[ 0 ]->{ controversy_dump_time_slices_id };

    my $to_tags_id_clause = '';
    if ( $to_tags_id )
    {
        if ( $to_tags_id eq 'other' )
        {
            $to_tags_id_clause = <<END;
and sl.ref_stories_id not in ( select stories_id from tagged_stories ts where ts.tags_id = \$2 )
END
        }
        elsif ( $to_tags_id =~ /^\d+$/ )
        {
            $to_tags_id += 0;
            $to_tags_id_clause = <<END;
and sl.ref_stories_id in ( select stories_id from tagged_stories ts where ts.tags_id = $to_tags_id )
END
        }
        else
        {
            die( "pseudo query error: second argument to link_field pseudo query clause must be an integer" );
        }
    }

    my $stories_ids = $db->query( <<END, $cdts_id, $from_tags_id )->flat;
with tagged_stories as (
    select stm.stories_id, stm.tags_id from stories_tags_map stm
    union
    select s.stories_id, mtm.tags_id from stories s join media_tags_map mtm on ( s.media_id = mtm.media_id )
)
    
select sl.ref_stories_id
    from
        cd.story_links sl
    where
        sl.controversy_dump_time_slices_id = \$1 and
        ( sl.source_stories_id in ( select stories_id from tagged_stories ts where ts.tags_id = \$2 ) )
        $to_tags_id_clause        
END

    return { stories_ids => $stories_ids };
}

# accept a single {? ... } clause and return a stories_id:(...) clause
sub _transform_clause
{
    my ( $clause ) = @_;

    my $db = MediaWords::DB::connect_to_db;

    # make a list of all calls to make against all field functions
    my $field_function_calls = {};
    while ( $clause =~ /(\w+):([\w-]+)/g )
    {
        my ( $field_name, $args_list ) = ( $1, $2 );

        my $args = [ split( '-', $args_list ) ];

        push( @{ $field_function_calls->{ $field_name } }, $args );
    }

    # call the field functions in the order in FIELD_FUNCTIONS and append the
    # return data to the $return_data hash
    my $return_data = {};
    my $stories_ids;
    for my $field_function ( @{ $FIELD_FUNCTIONS } )
    {
        my ( $field_name, $field_function, $num_args ) = @{ $field_function };

        if ( my $calls = $field_function_calls->{ $field_name } )
        {
            for my $call_args ( @{ $calls } )
            {
                die( "pseudo query error: $field_name pseudo query field requires at least $num_args arguments" )
                  unless ( @{ $call_args } >= $num_args );

                my $r = $field_function->( $db, $return_data, @{ $call_args } );
                push( @{ $return_data->{ $field_name } }, $r );
                if ( $r->{ stories_ids } && $stories_ids )
                {
                    my $lc = List::Compare->new( { lists => [ $stories_ids || [], $r->{ stories_ids } ], unsorted => 1 } );
                    $stories_ids = $lc->get_intersection_ref;
                }
                elsif ( !$stories_ids )
                {
                    $stories_ids = $r->{ stories_ids };
                }

            }
        }

        delete( $field_function_calls->{ $field_name } );
    }

    if ( my @remaining_fields = keys( %{ $field_function_calls } ) )
    {
        die( "pseudo query error: unknown pseudo query fields: " . join( ", ", @remaining_fields ) );
    }

    die( "pseudo query error: pseudo query fields failed to return any story ids" ) unless ( $stories_ids );

    if ( @{ $stories_ids } > 0 )
    {
        return 'stories_id:(' . join( ' ', @{ $stories_ids } ) . ')';
    }
    else
    {
        return 'stories_id:0';
    }
}

# transform the pseudo clauses in a query to stories_id:(...) clauses
sub transform_query
{
    my ( $q ) = @_;

    return undef unless ( defined( $q ) );

    my $t = $q;

    $t =~ s/(\{\?[^\}]*\})/_transform_clause( $1 )/eg;

    print STDERR "transformed solr query: '$q' -> '$t'\n" unless ( $t eq $q );

    return $t;
}

1;
