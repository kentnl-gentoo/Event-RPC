# $Id: Makefile.PL,v 1.2 2005/04/15 21:11:49 joern Exp $

use strict;
use ExtUtils::MakeMaker;

my $loop_modules = 0;
eval { require Event } && ++$loop_modules;
eval { require Glib }  && ++$loop_modules;

if ( !$loop_modules ) {
    print "\n";
    print "*******************************************************\n";
    print "WARNING: You need Event or Glib for Event::RPC to work!\n";
    print "*******************************************************\n";
    print "\n";
}

eval { require IO::Socket::SSL } || do {
    print "\n";
    print "NOTE: Event::RPC is capable of SSL encrypted connections,\n";
    print "      but your Perl is missing the IO::Socket::SSL module.\n";
    print "\n";
};

WriteMakefile(
    'NAME'	   => 'Event::RPC',
    'VERSION_FROM' => 'lib/Event/RPC.pm',
    'PREREQ_PM'    => {
    	'Test::More'	=> 0,
    },
    'dist' => {
        COMPRESS => "gzip",
        SUFFIX   => "gz",
	PREOP    => q[pod2text lib/Event/RPC.pm > README],
	POSTOP	 => q[mkdir -p dist && mv Event-RPC-*tar.gz dist/],
    },
);
