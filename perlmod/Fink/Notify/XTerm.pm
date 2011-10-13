# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Notify::XTerm module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2009-2011 The Fink Package Manager Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA.
#

package Fink::Notify::XTerm;
use warnings;
use strict;

use Fink::Notify;

our @ISA = qw(Fink::Notify);
our $VERSION = 1.00;

sub about {
	my $self = shift;

	my @about = ('XTerm', $VERSION, 'Terminal title-bar notification');
	return wantarray? @about : \@about;
}

sub events {
    my @eventlist = ();  # this is a non-standard notifier!
	return wantarray? @eventlist : \@eventlist;
}

sub new {
	my $class = shift;

	my $self = bless({}, $class);
	my @events = $self->events();

	return $self;
}

sub do_notify {
	my $self  = shift;

	# this notifier is hacked directly into Engine.pm (need to factor
	# out) and does not use the standard event-type triggers (need to
	# add new events). FIXME!

	return 1;
}

1;

# vim: ts=4 sw=4 noet
