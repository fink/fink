# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::SelfUpdate::Base class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2007 The Fink Package Manager Team
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

package Fink::SelfUpdate::Base;

use strict;
use warnings;

=head1 NAME

Fink::SelfUpdate::Base - base class for selfupdate-method classes

=head1 DESCRIPTION

Each method of selfupdating will soon be encapsulated in a
Fink::SelfUpdate::$method class, which are subclasses of the
Fink::SelfUpdate::Base class. There are stub methods for the public
interface calls, so a $method class only needs to override as needed.
All calls are class methods at this time.

=over 4

=item system_check

	my $boolean = Fink::SelfUpdate::$method->system_check();

Determine whether this method can be used on this machine. Make sure
needed external executables are present, etc. Must be over-ridden.

=cut

sub system_check { warn "Not implemented\n"; return 0; }

=item clear_metadata

  Fink::SelfUpdate::$method->clear_metadata();

Remove all metadata files and other structures related to this
selfupdate class (example: CVS/ directories).

=cut

sub clear_metadata {}

=item stamp_set

  Fink::SelfUpdate::$method->stamp_set();

=item stamp_clear

  Fink::SelfUpdate::$method->stamp_clear();

=item stamp_check

  my $boolean = Fink::SelfUpdate::$method->stamp_check();

Create, remove, or check presence of stamp file for this selfupdate
class. I don't know what these are for.

=cut

sub stamp_set {}

sub stamp_clear {}

sub stamp_check { return 0; }

=item do_direct

	Fink::SelfUpdate::$method->do_direct();

This implements the actual selfupdate sync process. Must be
over-ridden (obviously).

=cut

sub do_direct { die "Not implemented\n" }

=back

=cut

### EOF
1;
# vim: ts=4 sw=4 noet
