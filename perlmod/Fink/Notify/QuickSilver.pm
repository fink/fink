# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Notify::QuickSilver module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2005 The Fink Package Manager Team
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

package Fink::Notify::QuickSilver;

use Fink::Notify;
use Fink::Config qw($basepath);

our @ISA = qw(Fink::Notify);
our $VERSION = ( qw$Revision$ )[-1];

our $command = '/usr/bin/osascript';

sub about {
	my $self = shift;

	my @about = ('QuickSilver', $VERSION);
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

	my $title = $args{'title'};
	$title =~ s/\"/\\\"/gs;

	my $text = $args{'description'};
	$text =~ s/\"/\\\"/gs;

	$text = sprintf('tell application "QuickSilver" to show notification "%s" text "%s" image "com.apple.Terminal"', $title, $text);

	open(COMMAND, "| $command") or return undef;
	print COMMAND $text;
	close(COMMAND) or return undef;

	return 1;
}
