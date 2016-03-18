package MediaWords::Solr::PseudoQueries;

use strict;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

=head1 NAME

MediaWords::Solr::PseudoQueries - transform pseudo query clauses in solr queries

=head1 DESCRIPTION

Transform pseudo query clauses in solr queries.

Pseudo queries allow us to effectively perform joins with postgres queries directly through the api with queries that
look like:

sentence:obama and {~ controversy_dump_time_slice:1234 }

which would be processed and replaced before sending to solr with something that looks like:

sentence:obama and stories_id:( ... )

This module is integrated directly into MediaWords::Solr::query, so it shouldn't need to be called directly by the user
to query solr.

Documentation of the specific pseudo queries is in the api spec at doc/api_2_0_spec/api_2_0_spec.md and rendered at

https://github.com/berkmancenter/mediacloud/blob/master/doc/api_2_0_spec/api_2_0_spec.md#apiv2stories_publiclist

=cut

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
#
# if you add a new psuedo query field, update the pseudo query documentation in
# in the api documentation referenced in the DESCRIPTION above.
Readonly my $FIELD_FUNCTIONS => [
    [ 'controversy',                 \&_transform_controversy_field,                 1 ],
    [ 'controversy_dump_time_slice', \&_transform_controversy_dump_time_slice_field, 1 ],
    [ 'link_from_tag',               \&_transform_link_from_tag_field,               1 ],
    [ 'link_to_story',               \&_transform_link_to_story_field,               1 ],
    [ 'link_from_story',             \&_transform_link_from_story_field,             1 ],
    [ 'link_to_medium',              \&_transform_link_to_medium_field,              1 ],
    [ 'link_from_medium',            \&_transform_link_from_medium_field,            1 ],
];

# die with an error for the given field if there is no controversy_dump_time_slice
# field in the same query
sub _require_cdts
{
    my ( $return_data, $field ) = @_;

    die( "pseudo query error: '$field' field requires a controversy_dump_time_slice field in the same pseudo query clause" )
      unless ( $return_data->{ controversy_dump_time_slice } );
}

# transform link_to_story:1234 into list of stories within time slice that link
# to the given story
sub _transform_link_to_story_field
{
    my ( $db, $return_data, $to_stories_id ) = @_;

    _require_cdts( $return_data, 'link_to_story' );

    my $stories_ids = $db->query( <<END, $to_stories_id )->flat;
select source_stories_id
    from dump_story_links
    where
        ref_stories_id = ?
END

    return { stories_ids => $stories_ids };
}

# transform link_from_story:1234 into list of stories within time slice that are
# linked from the given story
sub _transform_link_from_story_field
{
    my ( $db, $return_data, $from_stories_id ) = @_;

    _require_cdts( $return_data, 'link_from_story' );

    my $stories_ids = $db->query( <<END, $from_stories_id )->flat;
select ref_stories_id
    from dump_story_links
    where source_stories_id = ?
END

    return { stories_ids => $stories_ids };
}

# transform link_to_medium:1234 into list of stories within time slice that link
# to the given medium
sub _transform_link_to_medium_field
{
    my ( $db, $return_data, $to_media_id ) = @_;

    _require_cdts( $return_data, 'link_from_medium' );

    my $stories_ids = $db->query( <<END, $to_media_id )->flat;
select distinct sl.source_stories_id
    from
        dump_story_links sl
        join dump_stories s
            on ( sl.ref_stories_id = s.stories_id )
    where
        s.media_id = \$1
END

    return { stories_ids => $stories_ids };
}

# transform link_from_medium:1234 into list of stories within time slice that are linked
# from the given medium
sub _transform_link_from_medium_field
{
    my ( $db, $return_data, $from_media_id ) = @_;

    _require_cdts( $return_data, 'link_from_medium' );

    my $stories_ids = $db->query( <<END, $from_media_id )->flat;
select distinct sl.ref_stories_id
    from
        dump_story_links sl
        join dump_stories s
            on ( sl.source_stories_id = s.stories_id )
    where
        s.media_id = \$1
END

    return { stories_ids => $stories_ids };
}

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
    my ( $db, $return_data, $cdts_id, $live ) = @_;

    my $cdts = $db->find_by_id( 'controversy_dump_time_slices', $cdts_id )
      || die( "Unable to find controversy_dump_time_slice with id '$cdts_id'" );
    my $controversy = $db->query( <<END, $cdts->{ controversy_dumps_id } )->hash;
select distinct c.*
    from
        controversies c
        join controversy_dumps cd on ( c.controversies_id = cd.controversies_id )
    where
        cd.controversy_dumps_id = ?
END

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, $live );

    my $stories_ids = $db->query( "select stories_id from dump_story_link_counts" )->flat;

    return { controversy_dump_time_slices_id => $cdts_id, stories_ids => $stories_ids, live => $live };
}

# accept link_from_tag:1234[-5678] clause and return a list of stories_ids where
# the stories are those that from stories tagged with the first tags_id (either directly
# or through media) and optionally link to stories tagged with the second tags_id.  if
# the second tags_id is 'other', return stories link from the first tags_id and linking
# to any story but the given tags_id.
sub _transform_link_from_tag_field
{
    my ( $db, $return_data, $from_tags_id, $to_tags_id ) = @_;

    $from_tags_id += 0;
    $to_tags_id   += 0;

    _require_cdts( $return_data, 'link_from_tag' );

    my $to_tags_id_clause = '';
    if ( $to_tags_id )
    {
        if ( $to_tags_id eq 'other' )
        {
            $to_tags_id_clause = <<END;
and sl.ref_stories_id not in ( select stories_id from tagged_stories ts where ts.tags_id != $from_tags_id )
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

    my $stories_ids = $db->query( <<END )->flat;
with tagged_stories as (
    select stm.stories_id, stm.tags_id from dump_stories_tags_map stm
    union
    select s.stories_id, mtm.tags_id from dump_stories s join media_tags_map mtm on ( s.media_id = mtm.media_id )
)

select sl.ref_stories_id
    from
        dump_story_links sl
    where
        ( sl.source_stories_id in ( select stories_id from tagged_stories ts where ts.tags_id = $from_tags_id ) )
        $to_tags_id_clause
END

    $db->commit;

    return { stories_ids => $stories_ids };
}

# accept a single {~ ... } clause and return a stories_id:(...) clause
sub _transform_clause
{
    my ( $clause ) = @_;

    my $db = MediaWords::DB::connect_to_db;

    $db->begin;

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

    $db->commit;

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

=head2 transform_query( $q )

Given a solr query, transform the pseudo clauses in a query to stories_id:(...) clauses and return the transformed
solr query.

=cut

sub transform_query
{
    my ( $q ) = @_;

    return undef unless ( defined( $q ) );

    if ( ref( $q ) eq 'ARRAY' )
    {
        return [ map { transform_query( $_ ) } @{ $q } ];
    }

    my $t = $q;

    $t =~ s/(\{\~[^\}]*\})/_transform_clause( $1 )/eg;

    #print STDERR "transformed solr query: '$q' -> '$t'\n" unless ( $t eq $q );

    return $t;
}

1;
