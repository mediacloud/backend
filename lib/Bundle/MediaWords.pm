package Bundle::MediaWords;

use strict;
use warnings;

1;

__END__

=head1 CONTENTS

#Alien::Tidyp is needed in order to get the tidyp clibary that HTML::Tidy needs -- many modules below depend on HTML::Tidy
Alien::Tidyp

#Perl6::Say #Temporarily removing dependency since this module is no longer on cpan

Algorithm::Cluster

Class::Std

List::Uniq

List::Member

Hash::Merge

#Object::Signature is needed by Catalyst::Plugin but dependancy wasn't detected so we're explicitly adding it.

Object::Signature

Catalyst

Catalyst::Devel

Catalyst::Action::RenderView

Catalyst::Plugin::Unicode

Catalyst::Plugin::Session::Store::FastMmap

Catalyst::Plugin::ConfigLoader

Catalyst::Plugin::Static::Simple

Catalyst::Plugin::Session

Catalyst::Plugin::Session::State::Cookie

Catalyst::Plugin::StackTrace

Catalyst::Test

Catalyst::Controller::HTML::FormFu

Task::Catalyst

Date::Parse

Data::Sorting

DBIx::Simple

Graph

Graph::Layout::Aesthetic

GraphViz

Text::Similarity::Overlaps

Tie::Cache::LRU

CHI

Lingua::Stem::Snowball

HTML::TagCloud

HTML::TreeBuilder::XPath

DBIx::Class::Schema

XML::LibXML

DBD::Pg

XML::FeedPP

RDF::Simple::Parser

Net::Calais

Math::Round

Math::Random

Lingua::StopWords

Lingua::Sentence

List::Compare::Functional
List::Pairwise

URI::Split

IPC::System::Simple

Text::Trim

Term::Prompt

HTML::LinkExtractor

Regexp::Optimizer

IPC::Run3

Dir::Self

PDL

Perl::Tidy

Switch

HTML::FormFu

#-- Temporarily adding HTML::Strip - it's used in scripts and tests.
HTML::Strip

Arff::Util

Class::CSV

Text::Table

Array::Compare

#--  needed for ./script
IPC::System::Simple  
#-- needed for ./script
Parallel::ForkManager 

Pod::Simple -- dependancy not detected by cpan

# -- dependancy not detected by cpan
Module::CPANTS::Analyse

Feed::Find

YAML::Syck

parent

Data::Serializer

Bundle::Test

HTML::FormFu

WebService::Google::Language

Tie::Cache::LRU

Storable

Parallel::ForkManager

Config::Any

Data::Dumper

Data::Dump

Data::Page

DateTime

Devel::Peek

Digest::SHA

Fcntl

File::Path

File::Temp

File::Util

File::Slurp

Getopt::Long

HTML::Entities

HTTP::Request

HTTP::Request::Common

IO::Compress::Gzip

IO::Select

IO::Socket

IO::Uncompress::Gunzip

Lingua::ZH::WordSegmenter

Lingua::Identify::CLD

List::Compare

List::MoreUtils

List::Member

LWP::Simple

LWP::UserAgent

#Used by LWP::UserAgent internally and needed for https links to work
LWP::Protocol::https

MIME::Base64

Moose

Path::Class

Pod::Usage

Readonly

Regexp::Common

Smart::Comments

Test::Differences

Test::More

Test::Strict

Tie::IxHash

Time::HiRes

Time::Local

Try::Tiny

URI

URI::Escape

URI::URL

XML::LibXML::XPathContext

XML::Simple

XML::TreePP

Encode::HanConvert

Sys::SigAction

DateTime::Format::Pg

=head1 DESCRIPTION

Bundle for modules required by MediaWords;

