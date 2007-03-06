# -*- mode: Perl; tab-width: 4; -*-
# vim: ts=4 sw=4 noet
#
# Fink::SelfUpdate::CVS class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2007 The Fink Package Manager Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA	 02111-1307, USA.
#

package Fink::SelfUpdate::CVS;

use base qw(Fink::SelfUpdate::Base);

use Fink::Services qw(&execute);
use Fink::Config qw($basepath);
use Fink::Command qw(rm_f touch);

use strict;
use warnings;

=head1 NAME

Fink::SelfUpdate::CVS - download package descriptions from a CVS server

=head1 DESCRIPTION

=head2 Public Methods

See documentation for the Fink::SelfUpdate base class.

=cut

sub clear_metadata {
	my $class = shift;  # class method for now

	my $finkdir = "$basepath/fink";
	&execute("/usr/bin/find $finkdir -name CVS -type d -print0 | xargs -0 /bin/rm -rf");
}

sub stamp_set {
	my $class = shift;  # class method for now

	my $finkdir = "$basepath/fink";
	touch "$finkdir/dists/stamp-cvs-live";
}

sub stamp_clear {
	my $class = shift;  # class method for now

	my $finkdir = "$basepath/fink";
	rm_f "$finkdir/stamp-cvs-live", "$finkdir/dists/stamp-cvs-live";
}

sub stamp_check {
	my $class = shift;  # class method for now

	my $finkdir = "$basepath/fink";
	return (-f "$finkdir/stamp-cvs-live" || -f "$finkdir/dists/stamp-cvs-live");
}

=head2 Private Methods

None yet.

=over 4

=back

=cut

1;
