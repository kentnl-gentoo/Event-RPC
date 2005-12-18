# $Id: Makefile.PL,v 1.3 2005/12/18 13:47:35 joern Exp $

use strict;
use ExtUtils::MakeMaker;

my $loop_modules = 0;
my $has_event    = 0;
my $has_glib     = 0;

eval { require Event; $has_event = 1 } && ++$loop_modules;
eval { require Glib;  $has_glib  = 1 } && ++$loop_modules;

if ( !$loop_modules ) {
    print "\n";
    print "*******************************************************\n";
    print "WARNING: You need Event or Glib for Event::RPC to work!\n";
    print "*******************************************************\n";
    print "\n";
}

my $has_ssl;
eval { require IO::Socket::SSL; $has_ssl = 1 } || do {
    print "\n";
    print "NOTE: Event::RPC is capable of SSL encrypted connections,\n";
    print "      but your Perl is missing the IO::Socket::SSL module.\n";
    print "      Event::RPC works perfectly without the module, but you\n";
    print "      can't use SSL connections until IO::Socket::SSL is\n";
    print "      installed.\n";
    print "\n";
};

#-- Add found modules to PREREQ_PM, so CPAN Testers add
#-- version numbers of these modules to the reports, which
#-- are very important in case of failing tests.
my @add_prereq;
push @add_prereq, 'Event', 0           if $has_event;
push @add_prereq, 'Glib', 0            if $has_glib;
push @add_prereq, 'IO::Socket::SSL', 0 if $has_ssl;
push @add_prereq, 'Net::SSLeay', 0     if $has_ssl;

WriteMakefile(
    'NAME'	   => 'Event::RPC',
    'VERSION_FROM' => 'lib/Event/RPC.pm',
    'PREREQ_PM'    => {
    	'Test::More'       => 0,
        'Storable'         => 0,
        'IO::Socket::INET' => 0,
        @add_prereq,
    },
    'dist' => {
        COMPRESS => "gzip",
        SUFFIX   => "gz",
	PREOP    => q[pod2text lib/Event/RPC.pm > README],
	POSTOP	 => q[mkdir -p dist && mv Event-RPC-*tar.gz dist/],
    },
);
