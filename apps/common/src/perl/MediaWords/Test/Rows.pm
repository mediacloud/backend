package MediaWords::Test::Rows;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Regexp::Common;
use Test::More;


# test that got_rows matches expected_rows by checking for the same number of elements, the matching up rows in
# got_rows and expected_rows and testing whether each field in $test_fields matches
sub rows_match($$$$$)
{
    my ( $label, $got_rows, $expected_rows, $id_field, $test_fields ) = @_;

    ok( defined( $got_rows ), "$label got_rows defined" );

    # just return if the number is not equal to avoid printing a bunch of uncessary errors
    is( scalar( @{ $got_rows } ), scalar( @{ $expected_rows } ), "$label number of rows" ) || return;

    my $expected_row_lookup = {};
    map { $expected_row_lookup->{ $_->{ $id_field } } = $_ } @{ $expected_rows };

    for my $got_row ( @{ $got_rows } )
    {
        my $id           = $got_row->{ $id_field };
        my $expected_row = $expected_row_lookup->{ $id };

        # don't try to test individual fields if the row does not exist
        ok( $expected_row, "$label row with id $got_row->{ $id_field } is expected" ) || next;

        for my $field ( @{ $test_fields } )
        {
            my $got      = $got_row->{ $field }      // '';
            my $expected = $expected_row->{ $field } // '';

            ok( exists( $got_row->{ $field } ), "$label field $field exists" );

            # if got and expected are both numers, test using number equality so that 4 == 4.0
            if ( $expected =~ /^$RE{ num }{ real }$/ && $got =~ /^$RE{ num }{ real }$/ )
            {
                my $label = "$label field $field ($id_field: $id): got $got expected $expected";

                # for ints, test equality; if one is a float, use a small delta so that 0.333333 == 0.33333
                if ( $expected =~ /^$RE{ num }{ int }$/ && $got =~ /^$RE{ num }{ int }$/ )
                {
                    ok( $got == $expected, $label );
                }
                else
                {
                    ok( abs( $got - $expected ) < 0.00001, $label );
                }
            }

            # If expected looks like a database boolean, compare it as such
            elsif ( $expected eq 'f' or $expected eq 't' or $got eq 'f' or $got eq 't' )
            {
                $expected = normalize_boolean_for_db( $expected );
                $got      = normalize_boolean_for_db( $got );
                is( $got, $expected, $label );
            }
            else
            {
                is( $got, $expected, "$label field $field ($id_field: $id)" );
            }
        }
    }
}

# given the response from an api call, fetch the referred row from the given table in the database
# and verify that the fields in the given input match what's in the database
sub validate_db_row($$$$$)
{
    my ( $db, $table, $response, $input, $label ) = @_;

    my $id_field = "${ table }_id";

    ok( $response->{ $id_field } > 0, "$label $id_field returned" );
    my $db_row = $db->find_by_id( $table, $response->{ $id_field } );
    ok( $db_row, "$label row found in db" );

    for my $key ( keys( %{ $input } ) )
    {
        my $got      = $db_row->{ $key };
        my $expected = $input->{ $key };

        # If expected looks like a database boolean, compare it as such
        if ( $expected eq 'f' or $expected eq 't' or $got eq 'f' or $got eq 't' )
        {
            $expected = normalize_boolean_for_db( $expected );
            $got      = normalize_boolean_for_db( $got );
        }

        is( $got, $expected, "$label field $key" );
    }
}

1;
