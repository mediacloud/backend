#!/usr/bin/perl
#
## test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
        use lib "$FindBin::Bin/../lib";
        }

use MediaWords::Crawler::Extractor;
use Getopt::Long;
use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use HTML::TreeBuilder;
use Time::Duration;

sub fetch_content{
	my ($download) = @_;

    	my $path = $download->{path};
	
	#print "Path $path \n";

	my $path = $download->{path};
    	
	if ( !$download->{path} || ( $download->{state} ne "success" ) )
    	{
        	return undef;
    	}

    	#note redefine delimitor from '/' to '~'
    	$path =~ s~^.*/(content/.*.gz)$~$1~;
    	my $data_dir = MediaWords::Util::Config::get_config->{mediawords}->{data_dir};
    	$data_dir = "" if ( !$data_dir );
    	$path     = "" if ( !$path );
    	$path     = "$data_dir/$path";
    	my $content;
    	if ( -f $path )
    	{
		my $fh;
        	if ( !( $fh = IO::Uncompress::Gunzip->new($path) ) )
        	{	
            		return undef;
        	}

        	while ( my $line = $fh->getline )
        	{
            		$content .= $line;
        	}

        	$fh->close;

	}else{
		$path =~ s/\.gz$/.dl/;

        	if ( !open( FILE, $path ) )
        	{	
            		return undef;
        	}

        	while ( my $line = <FILE> )
        	{
            		$content .= $line;
        	}

	}

	#print $content;
	return $content;
    
}
sub main {
	#print "Hello";
	# Connect to database
	my $db = DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info);
	# SELECT
	my $downloads =
          $db->query( "SELECT d.* from downloads d "
              . "  where d.extracted= 'f' and d.type='content' and d.state='success' "
              . " order by stories_id asc "
              . "  limit 1000"
              );

	my $cnt = 0;
	my $start_time = time();

	while ( my $download = $downloads->hash() )
        {
		my $root = HTML::TreeBuilder->new;
		my $content = fetch_content($download);
		$root->parse($content);
		open(OUT,">tmp/$cnt.html");
		print OUT $root->as_HTML(undef, "  ");
		close OUT;
		$root->delete;
		#print $content;
		$cnt = $cnt + 1;
	}
	# GET THE STRING
	print "Runtime ", duration(time() - $start_time), ".\n";
	
	# PARSE
#	my $root = HTML::TreeBuilder->new;
	
}
main();
