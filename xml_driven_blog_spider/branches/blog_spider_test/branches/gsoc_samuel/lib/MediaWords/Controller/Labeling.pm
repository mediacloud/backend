package MediaWords::Controller::Labeling;

use strict;
use warnings;
use parent 'Catalyst::Controller';
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTML::LinkExtor; # allows you to extract the links off of an HTML page.
use Catalyst::Log;
use HTML::TreeBuilder;
use MediaWords::Crawler::Extractor;
use Getopt::Long;
use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use HTML::TreeBuilder;
use MediaWords::Util::Config;

=head1 NAME

MediaWords::Controller::Labeling - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

    $c->response->body('Matched MediaWords::Controller::Labeling in Labeling.');
}


=head1 AUTHOR

Samuel Louvan,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

=head2 list

=cut

sub list : Local
{
	my ( $self, $c, $media_id ) = @_;
	
	my $cnt = $c->request->params->{cnt} || 0;

	my $db = DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info);
   my $downloads =
          $db->query( "SELECT path from downloads d "
              . "  where d.extracted='f' and d.type='content' and d.state='success' "
              . " order by stories_id asc "
              . "  limit 100"
              );
	
	$c->log->debug("Counter in LIST: $cnt");
	$c->stash->{cnt} = $cnt;
	if ($cnt != 0){
		
	my $idx = 1;
	my $path;
	my $stop = 0; 
   my $web_dir = MediaWords::Util::Config::get_config->{mediawords}->{web_dir};
	while ( (my $download = $downloads->hash()) && $stop ne 1)
   {
		if ($cnt == $idx) {
				$c->log->debug($download->{path});
    			my $data_dir = MediaWords::Util::Config::get_config->{mediawords}->{data_dir};
				$path = $download->{path};
	 			$path =~ s~^.*/(content/.*.gz)$~$1~; 
         
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
    			}
    			else
    			{
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
#			$c->log->debug($content);
			my $dumpname = ">$web_dir/labeling/temp.html";
         open (LOG, $dumpname) or die "Couldn't open $dumpname: $!";
   		print LOG $content;
         close LOG;

			#open(OUT,">$web_dir/labeling/hello.html");
			#print OUT $content;
			#close OUT;
			$stop =1;
	my $root = HTML::TreeBuilder->new;
	my $tmp_file_name = "$web_dir/labeling/temp.html";
	$root->parse_file($tmp_file_name) || die $!;


	# Find header and body element
	my $header = $root->look_down('_tag', 'head');
	my $body = $root->look_down('_tag', 'body');

	my $scriptStr = "";
	
	#Get the Javascript function 
	open(IN,"<$web_dir/include/script.js");
	my @lines = <IN> ;
	foreach my $str (@lines) {
       		$scriptStr = $scriptStr.$str;
	}
	close IN;

	#Inject Javascript function into the head element
	my $script = HTML::Element->new('script');
	$script->push_content($scriptStr);
	$header->push_content($script);

	# Change body attribute to enable highlighting
	$body->attr('onMouseOver','block(event)');
	$body->attr('onMouseOut','unblock(event)');
	$body->attr('onMouseDown','retrieveElementInfo(event)');


	# Finish manipulate flush it out
	open(OUT,">$web_dir/labeling/hello.html");
	print OUT $root->as_HTML(undef, "  ");
	close OUT;

	#Destroy tree
	$root->delete;
		}
		$idx++;
   }
	

	}

	$c->stash->{template} = 'labeling/list.tt2';
}


sub iframe : Local
{
        my ( $self, $c, $media_id ) = @_;

        $c->stash->{template} = 'labeling/hello.html';
}

sub add_instance:Local
{
        my ( $self, $c, $media_id ) = @_;
		
		  # catch radiobutton param, content or  not content
		  my $contentType = $c->request->params->{contentType} || 'N/A';		  
		  	
		  # get all the text string
		  my $featureVectorStr; 
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtInnerHtml}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtInnerText}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtImgNum}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtInteractionNum}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtFormNum}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtOptionNum}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtTableNum}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtDivNum}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtLinkNum}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtParaNum}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtLinkToTextRatio}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtCenterX}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtCenterY}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtWidth}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtHeight}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtDOMHeight}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtHeaderAround}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtLinkLength}.",";
		  $featureVectorStr = $featureVectorStr.$c->request->params->{txtStringLength}.",";
		
		  if ($contentType eq "Main Content") {
				$featureVectorStr = $featureVectorStr."1";
		  }else {
				$featureVectorStr = $featureVectorStr."0";	
		  }
		  # execute query 	

    	  my $db = DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info);
		  $c->dbis->query("insert into trainingvector (sitetype,trainingdatatype,featurevector) values('news','content',?)",$featureVectorStr);
		  $c->log->debug("Content type is $contentType, featureVector is $featureVectorStr");
			$c->stash->{template} = 'labeling/list.tt2';
}
sub url_get_do : Local {

        #my ($self, $c) = @_;
	my ( $self, $c, $media_id ) = @_;

	# Get the URL parameter from the form
	my $url=$c->request->params->{url} || 'N/A'; 	

        # Start virtual browser, get the web page
	my $browser = LWP::UserAgent->new;
	$browser->timeout(20);

	my $request = HTTP::Request->new(GET => $url);
	my $response = $browser->request($request);

	if ($response->is_error()) {
		$c->log->debug("Browser error!");
		
	}
	
	# RESPONSE OK
	my $contents = $response->content();
	
        # Put in temp file for tree manipulation
	my $filename = ">./root/labeling/temp.html";
        open (LOG, $filename) or die "Couldn't open $filename: $!";
	print LOG $contents;
        close LOG;


	# Build HTML Tree
	my $root = HTML::TreeBuilder->new;
	$root->parse_file('./root/labeling/temp.html') || die $!;


	# Find header and body element
	my $header = $root->look_down('_tag', 'head');
	my $body = $root->look_down('_tag', 'body');

	my $scriptStr = "";
	
	#Get the Javascript function 
	open(IN,"<script.js");
	my @lines = <IN> ;
	foreach my $str (@lines) {
       		$scriptStr = $scriptStr.$str;
	}
	close IN;

	#Inject Javascript function into the head element
	my $script = HTML::Element->new('script');
	$script->push_content($scriptStr);
	$header->push_content($script);

	# Change body attribute to enable highlighting
	$body->attr('onMouseOver','block(event)');
	$body->attr('onMouseOut','unblock(event)');
	$body->attr('onMouseDown','retrieveElementInfo(event)');


	# Finish manipulate flush it out
	open(OUT,">./root/labeling/hello.html");
	print OUT $root->as_HTML(undef, "  ");
	close OUT;

	#Destroy tree
	$root->delete;
		
	#$c->log->debug("Value of \$contents is: ".$contents);
	#sleep(10);
	# Display the modified web page.
	$c->stash->{template} = 'labeling/list.tt2';

}

sub printHello {
	my $c = @_[0];
	$c->log->debug("SATU SATU AKU SAYANG IBU");
}
sub url_get_db : Local {
	my ( $self, $c, $media_id ) = @_;
	my $db = DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info);
	my $downloads =
          $db->query( "SELECT path from downloads d "
              . "  where d.extracted='f' and d.type='content' and d.state='success' "
              . " order by stories_id asc "
              . "  limit 100"
              );
	my $cnt = $c->request->params->{cnt} || 0;
	my $contentType = $c->request->params->{contentType} ||'N/A';
	
	$c->log->debug("CONTENT TYPE:::::::::::::::::::::::::::::::::::::::::::: $contentType");	
	if ($cnt){
		$c->log->debug("Cnt is $cnt");
	}else {
		$cnt = 0;
	}

	my $idx = 1;
	while ( my $download = $downloads->hash() )
   {
		if ($cnt == $idx) {
				$c->log->debug($download->{path});
		}
                #my $root = HTML::TreeBuilder->new;
                #my $content = fetch_content($download);
                #$root->parse($content);
                #open(OUT,">tmp/$cnt.html");
                #print OUT $root->as_HTML(undef, "  ");
                #close OUT;
                #$root->delete;
                #print $content;
      #if (!$c->stash->{cnt})  {
		#	$c->stash->{cnt} = $cnt;
		#}
		#else{
	#		$c->stash->{cnt} = $c->stash->{cnt} +1;
		$idx++;
	}
	#	my $value = $c->stash->{cnt};
	#	$c->log->debug("The value of \$value is $value");
	$cnt = $cnt +1;
	$c->log->debug("Counter in get DB: $cnt");
	my $ax = $cnt;
		$c->response->redirect($c->uri_for($self->action_for('list'),
            {cnt => $cnt}));

		#$c->log->debug($value);
                #$cnt = $cnt + 1;
#                $c->log->debug($cnt->stash->cnt());
        #}
                
	$c->stash->{template} = 'labeling/list.tt2';

} 
1;

