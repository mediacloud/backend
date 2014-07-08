package Data::Google::Visualization::DataTable::MediaWords;

# local subclass of DBIx::Simple with some modification for use in media cloud code

use strict;
use warnings;

use Carp;

use Data::Dumper;

use base qw(Data::Google::Visualization::DataTable);

# STATICS

# cache of table primary key columns
my $_primary_key_columns = {};

# METHODS

sub new
{
    my $proto = shift;
    my $class = ref( $proto ) || $proto;

    my $self = $class->SUPER::new();

    bless( $self, $class );

    return $self;
}

sub add_rows
{
    my ( $self, @rows_to_add ) = @_;

    # Loop over our input rows
    for my $row ( @rows_to_add )
    {

        my @columns;
        my $properties;

        # Map hash-refs to columns
        if ( ref( $row ) eq 'HASH' )
        {

            # Grab the properties, if they exist
            if ( exists $self->{ 'column_mapping' }->{ 'p' } )
            {
                $properties = delete $row->{ '_p' };
            }
            else
            {
                $properties = delete $row->{ 'p' };
            }

            # We can't be going forward unless they specified IDs for each of
            # their columns
            croak "All your columns must have IDs if you want to add hashrefs" . " as rows"
              unless $self->{ 'all_columns_have_ids' };

            # Loop through the keys, populating @columns
            for my $key ( keys %$row )
            {

                # Get the relevant column index for the key, or handle 'p'
                # properly
                unless ( exists $self->{ 'column_mapping' }->{ $key } )
                {
                    croak "Couldn't find a column with id '$key'";
                }
                my $index = $self->{ 'column_mapping' }->{ $key };

                # Populate @columns with the data-type and value
                $columns[ $index ] = [ $self->{ 'columns' }->[ $index ]->{ 'type' }, $row->{ $key } ];

            }

            # Map array-refs to columns
        }
        elsif ( ref( $row ) eq 'ARRAY' )
        {

            # Populate @columns with the data-type and value
            my $i = 0;
            for my $col ( @$row )
            {
                $columns[ $i ] = [ $self->{ 'columns' }->[ $i ]->{ 'type' }, $col ];
                $i++;
            }

            # Rows must be array-refs or hash-refs
        }
        else
        {
            croak "Rows must be array-refs or hash-refs: $row";
        }

        # Force the length of columns to be the same as actual columns, to
        # handle undef values better.
        $columns[ $self->{ 'column_count' } - 1 ] = undef
          unless defined $columns[ $self->{ 'column_count' } - 1 ];

        # Convert each cell in to the long cell format
        my @formatted_columns;
        for ( @columns )
        {
            if ( $_ )
            {
                my ( $type, $column ) = @$_;

                if ( ref( $column ) eq 'HASH' )
                {

                    # Check f is a simple string if defined
                    if ( defined( $column->{ 'f' } ) && ref( $column->{ 'f' } ) )
                    {
                        croak "Cell's 'f' values must be strings: " . $column->{ 'f' };
                    }

                    # If p is defined, check it serializes
                    if ( defined( $column->{ 'p' } ) )
                    {
                        croak "'p' must be a reference"
                          unless ref( $column->{ 'p' } );
                        eval { $self->json_xs_object->encode( $column->{ 'p' } ) };
                        croak "Serializing 'p' failed: $@" if $@;
                    }

                    # Complain about any unauthorized keys
                    if ( $self->pedantic )
                    {
                        for my $key ( keys %$column )
                        {
                            carp "'$key' is not a recognized key"
                              unless $key =~ m/^[fvp]$/;
                        }
                    }
                    push( @formatted_columns, [ $type, $column ] );
                }
                else
                {
                    push( @formatted_columns, [ $type, { v => $column } ] );
                }

                # Undefined that become nulls
            }
            else
            {
                push( @formatted_columns, [ 'null', { v => undef } ] );
            }
        }

        # Serialize each cell
        my @cells;
        for ( @formatted_columns )
        {
            my ( $type, $cell ) = @$_;

            # Force 'f' to be a string
            if ( defined( $cell->{ 'f' } ) )
            {
                $cell->{ 'f' } .= '';
            }

            # Handle null/undef
            if ( !defined( $cell->{ 'v' } ) )
            {
                push( @cells, $self->json_xs_object->encode( $cell ) );

                # Convert boolean
            }
            elsif ( $type eq 'boolean' )
            {
                $cell->{ 'v' } = $cell->{ 'v' } ? \1 : \0;
                push( @cells, $self->json_xs_object->encode( $cell ) );

                # Convert number
            }
            elsif ( $type eq 'number' )
            {
                $cell->{ 'v' } = 0 unless $cell->{ 'v' };    # Force false values to 0
                $cell->{ 'v' } += 0;                         # Force numeric for JSON encoding
                push( @cells, $self->json_xs_object->encode( $cell ) );

                # Convert string
            }
            elsif ( $type eq 'string' )
            {
                $cell->{ 'v' } .= '';
                push( @cells, $self->json_xs_object->encode( $cell ) );

                # It's a date!
            }
            else
            {
                my @date_digits;

                # Date digits specified manually
                if ( ref( $cell->{ 'v' } ) eq 'ARRAY' )
                {
                    @date_digits = @{ $cell->{ 'v' } };

                    # We're going to have to retrieve them ourselves
                }
                else
                {
                    my @initial_date_digits;

                    # Epoch timestamp
                    if ( !ref( $cell->{ 'v' } ) )
                    {
                        my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime( $cell->{ 'v' } );
                        @initial_date_digits = ( $year, $mon, $mday, $hour, $min, $sec );

                    }
                    elsif ( $cell->{ 'v' }->isa( 'DateTime' ) )
                    {
                        my $dt = $cell->{ 'v' };
                        @initial_date_digits =
                          ( $dt->year, ( $dt->mon - 1 ), $dt->day, $dt->hour, $dt->min, $dt->sec, $dt->millisecond );

                    }
                    elsif ( $cell->{ 'v' }->isa( 'Time::Piece' ) )
                    {
                        my $tp = $cell->{ 'v' };
                        @initial_date_digits = ( $tp->year, $tp->_mon, $tp->mday, $tp->hour, $tp->min, $tp->sec );

                    }
                    else
                    {
                        croak "Unknown date format";
                    }

                    if ( $type eq 'date' )
                    {
                        @date_digits = @initial_date_digits[ 0 .. 2 ];
                    }
                    elsif ( $type eq 'datetime' )
                    {
                        @date_digits = @initial_date_digits[ 0 .. 5 ];
                    }
                    else
                    {    # Time of day
                        @date_digits = @initial_date_digits[ 3, -1 ];
                    }
                }

                my $json_date = join ', ', @date_digits;
                if ( $type eq 'timeofday' )
                {
                    $json_date = '[' . $json_date . ']';
                }
                else
                {
                    $json_date = '"Date( ' . $json_date . ' )"';
                }

                my $placeholder = '%%%PLEHLDER%%%';
                $cell->{ 'v' } = $placeholder;
                my $json_string = $self->json_xs_object->encode( $cell );
                $json_string =~ s/"$placeholder"/$json_date/;
                push( @cells, $json_string );
            }
        }

        my %data = ( cells => \@cells );
        $data{ 'properties' } = $properties if defined $properties;

        push( @{ $self->{ 'rows' } }, \%data );
    }

    return $self;
}

1;
