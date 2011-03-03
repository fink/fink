# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::SelfUpdate::Base class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2007-2011 The Fink Package Manager Team
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
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA.
#

package Fink::SelfUpdate::Base;

use Fink::CLI qw(&print_breaking_stderr);
use Fink::Config qw($basepath $distribution);

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

=item description

	my $label = Fink::SelfUpdate::$method->description();

Returns a short description of this method, similar to the Description
field of a package. Defaults to the package-name (no leading classes)
as lower-case.

=cut

sub description {
	require Fink::SelfUpdate;
	&Fink::SelfUpdate::class2methodname($_[0]);
}

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

=item do_direct

	my $data = Fink::SelfUpdate::$method->do_direct();

This implements the actual selfupdate sync process. Must be
over-ridden (obviously). Returns boolean indicating success. Must call
Fink::SelfUpdate::$method->do_direct before returning.

=cut

sub do_direct { die "Not implemented\n" }

=item update_version_file

	Fink::SelfUpdate::$method->update_version_file(%options);

Records information in %p/fink/$distribution/VERSION.selfupdate about
the just-done selfupdate. Returns nothing useful. Probably safest to
avoid overriding this class method. The following %options are known:

=over 4

=item distribution (optional)

Updates the VERSION file for the given value. Defaults to the
currently active distribution.

=item data (optional)

A single line of text containing method-specific information
(point-update version number, remote server info, etc).

=back

=cut

sub update_version_file {
	my $class = shift;
	my %options = ('distribution' => $distribution, 'data' => '', @_);

	my $filename = "$basepath/fink/$options{distribution}/VERSION.selfupdate";
	my @lines = ();

	# read old file
	if (open my $FH, '<', $filename) {
		@lines = <$FH>;
		close $FH;
	}
	chomp @lines;

	# remove old selfupdate info
	@lines = grep { $_ !~ /^\s*SelfUpdate\s*:/i } @lines;

	# add new selfupdate info
	require Fink::SelfUpdate;
	my $line = sprintf 'SelfUpdate: %s@%s', Fink::SelfUpdate::class2methodname($class), time();
	$line .= " $options{data}" if length $options{data};
	push @lines, $line;

	# save new file contents atomically
	if (open my $FH, '>', "$filename.tmp") {
		print $FH map "$_\n", @lines;
		close $FH;
		unlink $filename;
		rename "$filename.tmp", $filename;
	} else {
		print_breaking_stderr "WARNING: Not saving timestamp of selfupdate because could not write $filename.tmp: $!\n";
	}
}

=back

=cut

### EOF
1;
# vim: ts=4 sw=4 noet
