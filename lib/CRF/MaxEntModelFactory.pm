#!/usr/bin/perl -w

package MaxEntModelFactory;

use strict;
use warnings;

use 5.14.1;

use  Inline ( Java => 'STUDY',
	      STUDY => [ 'java.io.File' ],
    );


use Inline (
      Java => 'STUDY',
      STUDY => ['java.io.File'],
   ) ;

use  Inline ( Java => 'STUDY',
	      STUDY => [ qw ( opennlp.maxent.BasicEventStream opennlp.maxent.GIS
opennlp.maxent.PlainTextByLineDataStream opennlp.maxent.RealBasicEventStream opennlp.maxent.io.GISModelWriter opennlp.maxent.io.SuffixSensitiveGISModelWriter java.io.FileReader java.io.File ) ],
	      AUTOSTUDY => 1,
	      CLASSPATH => '/home/dlarochelle/Dropbox/SCOTUS_Data2/apache-opennlp-1.5.2-incubating-src/opennlp-maxent/target/opennlp-maxent-3.0.2-incubating.jar',
	      PACKAGE => 'main'
    );


sub create_model
{
    my ( $data_file_name, $iterations ) = @_;
    
    my $real = 0;
    my $USE_SMOOTHING = 0;

use  Inline ( Java => 'STUDY',
	      STUDY => [ 'java.io.File' ],
    );


use Inline (
      Java => 'STUDY',
      STUDY => ['java.io.File'],
   ) ;

    my $io_file = new java::io::File($data_file_name);
    my $datafr = new java::io::FileReader( $io_file );
    my $es;
    if (!$real) { 
          $es = new opennlp::maxent::BasicEventStream(new opennlp::maxent::PlainTextByLineDataStream($datafr));
        }
        else {
          $es = new opennlp::maxent::RealBasicEventStream(new opennlp::maxent::PlainTextByLineDataStream($datafr));
        }

         $opennlp::maxent::GIS->{SMOOTHING_OBSERVATION} = 0.1;

        my $model;
    if (!$real) {
	$model = opennlp::maxent::GIS->trainModel($es, $iterations, 0, $USE_SMOOTHING, 1);
    }
    
    return $model;
}

sub save_model
{
    my ( $model, $output_file_name ) = @_;
    my $outputFile = new java::io::File( $output_file_name );

    my $writer =  new opennlp::maxent::io::SuffixSensitiveGISModelWriter($model, $outputFile);

    $writer->persist(); 
}

1;
