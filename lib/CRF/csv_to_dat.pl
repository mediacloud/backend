#!/usr/bin/perl -w

use strict;

#use 5.14.0;
use 5.10.0;

use Text::CSV;
use Class::CSV;
use Readonly;
use Data::Dumper;

#get_fields
my $text_csv = Text::CSV->new ( { binary => 1 } )  # should set binary attribute.
                 or die "Cannot use CSV: ".Text::CSV->error_diag ();
 
my $usage = 'perl csv_to_dat.pl CSV_FILE' ;
die "$usage" unless scalar (@ARGV) >= 1;

my $csv_file_name = $ARGV[0];

open my $fh, "<:encoding(utf8)", $csv_file_name or die "$csv_file_name: $!";
my $fields = $text_csv->getline( $fh );

#say STDERR Dumper($fields);

$text_csv = 0;
close( $fh );

say STDERR "starting csv parse";

my $csv = Class::CSV->parse(
    filename => $csv_file_name,
    fields   => $fields
  );

say STDERR "finished csv parse";

my @lines = @{$csv->lines()};

shift @lines;

$csv->lines( \@lines );

my $indep_var_fields = [ @ { $fields } ];

pop @ { $ indep_var_fields };

for my $line ( @ { $csv->lines() } )
{
    for my $indep_var_field ( @ { $indep_var_fields } )
    {

	my $field_val = $line->get( $indep_var_field ) ;
	## Don't include false features.

	next if ( $field_val == 0 );

	print "$indep_var_field=";
	die unless defined( $field_val );

	if ( $field_val == 1 )
	{
	    print "true";
	}
	else
	{
	    die unless $field_val == 0;
	    print "false";
	}

	print " ";
    }

    say $line->get( 'class' );
}
