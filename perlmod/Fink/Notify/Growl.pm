# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Notify::Growl module
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

package Fink::Notify::Growl;

use Fink::Notify;
use Fink::Config qw($basepath);

our @ISA = qw(Fink::Notify);
our $VERSION = ( qw$Revision$ )[-1];

sub about {
	my $self = shift;

	my @about = ('Growl', $VERSION);
	return wantarray? @about : \@about;
}

sub new {
	my $class = shift;

	my $self = bless({}, $class);
	my @events = $self->events();

	eval {
		require Mac::Growl;
		Mac::Growl::RegisterNotifications("Fink", \@events, \@events);
	};
	return $@ ? undef : $self;
}

sub do_notify {
	my $self  = shift;
	my %args  = @_;

	my $image = $basepath . '/share/fink/images/' . $args{'event'} . '.png';
	$image = undef unless -r $image;

	my $sticky = ($args{'event'} =~ /Failed$/);

	eval {
		Mac::Growl::PostNotification("Fink", $args{'event'}, $args{'title'}, $args{'description'}, $sticky, 0, $image);
	};
	return $@ ? undef : 1;
}
