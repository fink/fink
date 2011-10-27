# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Notify::Say module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2011 The Fink Package Manager Team
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

package Fink::Notify::Say;
use warnings;
use strict;

use Fink::Notify;
use Fink::Config qw($basepath);

our @ISA = qw(Fink::Notify);
our $VERSION = 1.00;

our $command = '/usr/bin/osascript';

sub about {
	my $self = shift;

	my @about = ('Say', $VERSION, 'Text-to-speech audible notification');
	return wantarray? @about : \@about;
}

sub new {
	my $class = shift;

	my $self = bless({}, $class);
	my @events = $self->events();

	return -x $command ? $self : undef;
}

sub do_notify {
	my $self  = shift;
	my %args  = @_;

	my $text = $args{'description'};
	$text =~ s/\"/\\\"/gs;

	$text = sprintf('say "%s"', $text);

	system($command, "-e", $text) == 0 or return undef;

	return 1;
}

1;

# vim: ts=4 sw=4 noet
