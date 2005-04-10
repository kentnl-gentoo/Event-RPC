# $Id: Event.pm,v 1.1 2005/04/10 21:07:12 joern Exp $

#-----------------------------------------------------------------------
# Copyright (C) 2002-2005 Jörn Reder <joern AT zyn.de>.
# All Rights Reserved. See file COPYRIGHT for details.
# 
# This module is part of Event::RPC, which is free software; you can
# redistribute it and/or modify it under the same terms as Perl itself.
#-----------------------------------------------------------------------

package Event::RPC::Loop::Event;

use base qw( Event::RPC::Loop );

use strict;
use Event;

sub add_io_watcher {
	my $self = shift;
	my %par = @_;
	my ($fh, $cb, $desc, $poll) = @par{'fh','cb','desc','poll'};

	return Event->io (
		fd        => $fh,
		poll      => $poll,
		cb        => $cb,
		desc      => $desc,
		reentrant => 0,
	);
}

sub del_io_watcher {
	my $self = shift;
	my ($watcher) = @_;

	$watcher->cancel;

	1;
}

sub add_timer {
	my $self = shift;
	my %par = @_;
	my  ($interval, $after, $cb, $desc) =
	@par{'interval','after','cb','desc'};

	die "interval and after can't be used together"
		if $interval && $after;

	return Event->timer (
		interval	=> $interval,
		after		=> $after,
		cb		=> $cb,
		desc		=> $desc,
	);
}

sub del_timer {
	my $self = shift;
	my ($timer) = @_;
	
	$timer->cancel;
	
	1;
}

sub enter {
	my $self = shift;

	Event::loop();

	1;
}

sub leave {
	my $self = shift;

	Event::unloop_all("ok");

	1;
}

1;

__END__

=head1 NAME

Event::RPC::Loop::Event - Event mainloop for Event::RPC

=head1 SYNOPSIS

  use Event::RPC::Server;
  use Event::RPC::Loop::Event;
  
  my $server = Event::RPC::Server->new (
      ...
      loop => Event::RPC::Loop::Event->new(),
      ...
  );

  $server->start;

=head1 DESCRIPTION

This modules implements a mainloop using the Event module
for the Event::RPC::Server module. It implements the interface
of Event::RPC::Loop. Please refer to the manpage of
Event::RPC::Loop for details.

=head1 AUTHORS

  Jörn Reder <joern at zyn dot de>

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2005 by Jörn Reder.

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
