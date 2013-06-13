#!/usr/bin/perl -w

use strict;

use 5.10.0;

use Text::CSV;
use Class::CSV;
use Readonly;
use Data::Dumper;
use File::Temp qw/ tempfile tempdir /;
use Env qw(HOME);
use File::Path qw(make_path remove_tree);
use MaxEntUtils;

Readonly my $folds => 10;

use Inline Java => <<'END_OF_JAVA_CODE' ;
class Pod_alu {
    public Pod_alu(){
    }
    
    public int add(int i, int j){
	return i + j ;
    }
    
    public int subtract(int i, int j){
	return i - j ;
    }
}
END_OF_JAVA_CODE
    
use Inline (
      Java => 'STUDY',
      STUDY => ['java.util.HashMap'],
   ) ;

   my $hm = new java::util::HashMap() ;

# use Inline (
#       Java => 'STUDY',
#       STUDY => ['java.io.File'],
#    ) ;

#    my $fio = new java::io::File( 'foo') ;
    my $alu = new Pod_alu() ;
print($alu->add(9, 16) . "\n") ; # prints 25
   print($alu->subtract(9, 16) . "\n") ; # prints -7

# use  Inline ( Java => 'STUDY',
# 	      STUDY => [ qw ( opennlp.maxent.BasicEventStream opennlp.maxent.GIS
# opennlp.maxent.PlainTextByLineDataStream opennlp.maxent.RealBasicEventStream opennlp.maxent.io.GISModelWriter opennlp.maxent.io.SuffixSensitiveGISModelWriter java.io.FileReader java.io.File ) ],
# 	      AUTOSTUDY => 1,
# 	      CLASSPATH => '/home/dlarochelle/Dropbox/SCOTUS_Data2/apache-opennlp-1.5.2-incubating-src/opennlp-maxent/target/opennlp-maxent-3.0.2-incubating.jar'
#     );

sub main
{
    my $usage = "USAGE: max_ent_create_model <dat_file> <num_iterations>";

    die "$usage" unless scalar (@ARGV) == 2;

    my $dat_file = $ARGV[0];
    
    say STDERR "dat file $dat_file";

    open my $in_fh, $dat_file or die "Failed to open file $@";

    my @out_data = <$in_fh>;   
    close $in_fh;

    my $iterations = $ARGV[1];

    die "Iterations must be numeric\n$usage" unless int($iterations) eq $iterations;

    $iterations = int($iterations);

    my $model_output_location = $dat_file; 
    $model_output_location =~ s/\.dat$/_MaxEntModel_Iterations_$iterations\.txt/;

    MaxEntUtils::create_model_inline_java( $dat_file, $iterations)
}

main();
