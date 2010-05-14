package MediaWords::Pg;

# utility modules for plperl functions

use strict;

use vars qw(@ISA @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = qw(exec_query query fetchrow cursor_close pg_log exec_prepared query_prepared freeplans);

my $in_pl_perl = 0;

# hash of spi functions and constants
my $_spi;

# cache of query plans
my $_plans;

# set the spi function or value in the hash
sub set_spi
{
    my ( $name, $value ) = @_;

    $_spi->{ $name } = $value;
}

# spi imported functions
sub exec_query   { return $_spi->{ spi_exec_query }->( @_ ); }
sub query        { return $_spi->{ spi_query }->( @_ ); }
sub fetchrow     { return $_spi->{ spi_fetchrow }->( @_ ); }
sub cursor_close { return $_spi->{ spi_cursor_close }->( @_ ); }
sub elog         { return $_spi->{ elog }->( @_ ); }

# spi imported constants
sub DEBUG   { return $_spi->{ DEBUG }; }
sub LOG     { return $_spi->{ LOG }; }
sub INFO    { return $_spi->{ INFO }; }
sub NOTICE  { return $_spi->{ NOTICE }; }
sub WARNING { return $_spi->{ WARNING }; }
sub ERROR   { return $_spi->{ ERROR }; }

# send a notice up to the postgres client and log
sub pg_log
{
    $_spi->{ elog }->( $_spi->{ NOTICE }, @_ );
}

# fetch cached plan or prepare new plan then execute it
sub exec_prepared
{
    my ( $query, $params, $args ) = @_;

    my $plan = $_plans->{ $query };
    if ( !$plan )
    {
        $plan = $_spi->{ spi_prepare }->( $query, @{ $params } );
        $_plans->{ $query } = $plan;
    }

    return $_spi->{ spi_exec_prepared }->( $plan, @{ $args } );
}

# fetch cached plan or prepare new plan then query it
sub query_prepared
{
    my ( $query, $params, $args ) = @_;

    my $plan = $_plans->{ $query };
    if ( !$plan )
    {
        $plan = $_spi->{ spi_prepare }->( $query, @{ $params } );
        $_plans->{ $query } = $plan;
    }

    return $_spi->{ spi_query_prepared }->( $plan, @{ $args } );
}

# free all cached plans
sub freeplans
{
    $_plans = {};
}

1;
