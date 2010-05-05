#!/usr/bin/perl

use Algorithm::SVM;
use Algorithm::SVM::DataSet;


open(ARFFDATA,"transform.arff");

  $svm = new Algorithm::SVM(Type   => 'C-SVC',
                            Kernel => 'radial',
                            Gamma  => 64,
                            C      => 8);
#my $ds3 = new Algorithm::SVM::DataSet(Label => 3);
my @tset;
while ($record = <ARFFDATA>) {
	my @attributes;
	#print $record;
	@attributes = split(/,/,$record);
	
	if ($attributes[scalar(@attributes)-1] == 1) {
		print "ISI:".$attributes[scalar(@attributes)-1]."\n";
		my $ds1 = new Algorithm::SVM::DataSet(Label => 1);
		print "Masuk sini";
		$ds1->attribute($_, $attributes[$_ - 2]) for(1..scalar(@attributes)-1);
		push(@tset,$ds1);
		my $attr =$ds1->attribute(5);
		#print "$attr"." Class Label :".$ds1->attribute(6);
	}else {
		my $ds2 = new Algorithm::SVM::DataSet(Label => 0);
		$ds2->attribute($_, $attributes[$_ - 2]) for(1..scalar(@attributes)-1);
		push(@tset,$ds2);
		print "Masuk sana";
		my $attr = $ds2->attribute(5);
		#print "$attr"." Class Label :".$ds2->attribute(6);
	}
#	print @attributes;
	print "\n";
}


$svm->train(@tset);
my $accuracy = $svm->validate(5);
$svm->save('news-ku.model');
print "Accuracy : $accuracy"."\n";

#my @labels = $svm->getLabels();

#foreach $label (@labels) {
#	print $label;
#}
#print "Finish\n";
close(ARFFDATA);

