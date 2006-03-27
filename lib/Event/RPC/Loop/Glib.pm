# $Id: Glib.pm,v 1.2 2006/02/27 14:33:37 joern Exp $

#-----------------------------------------------------------------------
# Copyright (C) 2002-2006 Jörn Reder <joern AT zyn.de>.
# All Rights Reserved. See file COPYRIGHT for details.
# 
# This module is part of Event::RPC, which is free software; you can
# redistribute it and/or modify it under the same terms as Perl itself.
#-----------------------------------------------------------------------

package Event::RPC::Loop::Glib;

use base qw( Event::RPC::Loop );

use strict;
use Glib;

sub get_glib_main_loop		{ shift->{glib_main_loop}		}
sub set_glib_main_loop		{ shift->{glib_main_loop}	= $_[1]	}

sub add_io_watcher {
	my $self = shift;
	my %par = @_;
	my ($fh, $cb, $desc, $poll) = @par{'fh','cb','desc','poll'};

	my $cond = $poll eq 'r' ?
		['G_IO_IN', 'G_IO_HUP']:
		['G_IO_OUT','G_IO_HUP'];
	
	return Glib::IO->add_watch ($fh->fileno, $cond, sub { &$cb(); 1 } );
}

sub del_io_watcher {
	my $self = shift;
	my ($watcher) = @_;

	Glib::Source->remove ($watcher);

	1;
}

sub add_timer {
	my $self = shift;
	my %par = @_;
	my  ($interval, $after, $cb, $desc) =
	@par{'interval','after','cb','desc'};

	die "interval and after can't be used together"
		if $interval && $after;

	if ( $interval ) {
		return Glib::Timeout->add (
			$interval * 1000,
			sub { &$cb(); 1 }
		);
	} else {
		return Glib::Timeout->add (
			$after * 1000,
			sub { &$cb(); 0 }
		);
	}

	1;
}

sub del_timer {
	my $self = shift;
	my ($timer) = @_;
	
	Glib::Source->remove($timer);
	
	1;
}

sub enter {
	my $self = shift;
	
	Glib->install_exception_handler(sub {
		print "Event::RPC::Loop::Glib caught an exception: $@\n";
		1;
	});
	
	my $main_loop = Glib::MainLoop->new;
	$self->set_glib_main_loop($main_loop);
	
	$main_loop->run;

	1;
}

sub leave {
	my $self = shift;
	
	$self->get_glib_main_loop->quit;

	1;
}

1;

__END__

=head1 NAME

Event::RPC::Loop::Glib - Glib mainloop for Event::RPC

=head1 SYNOPSIS

  use Event::RPC::Server;
  use Event::RPC::Loop::Glib;
  
  my $server = Event::RPC::Server->new (
      ...
      loop => Event::RPC::Loop::Glib->new(),
      ...
  );

  $server->start;

=head1 DESCRIPTION

This modules implements a mainloop using Glib for the
Event::RPC::Server module. It implements the interface
of Event::RPC::Loop. Please refer to the manpage of
Event::RPC::Loop for details.

=head1 AUTHORS

  Jörn Reder <joern at zyn dot de>

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2006 by Jörn Reder.

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU Library General Public License as
published by the Free Software Foundation; either version 2.1 of the
License, or (at your option) any later version.

This library is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.

You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307
USA.

=cut
