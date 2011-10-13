# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Notify::Syslog module
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

package Fink::Notify::Syslog;
use warnings;
use strict;

use Fink::Notify;
use Fink::Config qw($basepath);

our @ISA = qw(Fink::Notify);
our $VERSION = 1.00;

our $command = '/usr/bin/logger';

sub about {
	my $self = shift;

	my @about = ('Syslog', $VERSION, 'Log notifications to /var/log/system.log');
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

	$args{'description'} =~ s/^[\r\n\s]+//gsi;
	$args{'description'} =~ s/[\r\n\s]+$//gsi;
	$args{'description'} =~ s/[\r\n]+/\n/gsi;

	my $errors = 0;

	for my $line (split(/\s*\n+/, $args{'description'})) {
		my $return = system($command, '-t', 'Fink', $line);
		if ($return >> 8) {
			$errors++;
		}
	}

	return $errors ? undef : 1;
}

1;

# vim: ts=4 sw=4 noet
