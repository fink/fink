# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Notify::Say module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2006 The Fink Package Manager Team
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA      02111-1307, USA.
#

package Fink::Notify::Say;

use Fink::Notify;
use Fink::Config qw($basepath);

our @ISA = qw(Fink::Notify);
our $VERSION = (qw$Revision$)[-1];

sub about {
	my $self = shift;

	my @about = ('Say', $VERSION);
	return wantarray? @about : \@about;
}

sub new {
	my $class = shift;

	my $self = bless({}, $class);
	my @events = $self->events();

	return undef unless (-x '/usr/bin/osascript');

	return $self;
}

sub do_notify {
	my $self  = shift;
	my %args  = @_;

	my $text = $args{'description'};
	$text =~ s/\"/\\\"/gs;

	$text = sprintf('say "%s"', $text);

	if (open(COMMAND, "| osascript")) {
		print COMMAND $text;
		close(COMMAND);
	} else {
		return undef;
	}

	return 1;
}

1;
