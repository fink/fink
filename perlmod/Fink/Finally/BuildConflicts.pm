# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Finally::BuildConflicts module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2006-2011 The Fink Package Manager Team
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

package Fink::Finally::BuildConflicts;
use base 'Fink::Finally';

use warnings;
use strict;

use Fink::CLI	qw(die_breaking print_breaking_stderr);
use Fink::Config;
use Fink::PkgVersion;

=head1 NAME

Fink::Finally::BuildConflicts - Remove and restore BuildConflicts during a
								Fink build.

=head1 DESCRIPTION

When a package has BuildConflicts, Fink::Finally::BuildConflicts will
remove any that are installed, and then restore them unconditionally
afterwards.

=head1 CLASS METHODS

=over 4

=item new

  my $buildconfs = Fink::Finally::BuildConflicts->new($pvs);

Remove the BuildConflicts packages in the array-ref $pvs, and restore them
when I<$bc> goes out of scope.

=cut

sub initialize {
	my ($self, $pvs) = @_;
	
	$self->{remove} = [ grep { $_->is_installed } @$pvs ];
	return unless @{$self->{remove}};
	
	my @cant_restore = grep { !$_->is_present } @{$self->{remove}};
	if (@cant_restore) {
		die_breaking "The following packages must be temporarily removed, but "
			. "there are no .debs to restore them from:\n  "
			. join(' ', sort map { $_->get_name } @cant_restore);
	}
	
	my @names = sort map { $_->get_name } @{$self->{remove}};
	my $names = join(' ', @names);
	
	print_breaking_stderr "Temporarily removing BuildConflicts:\n $names";
	Fink::PkgVersion::phase_deactivate(\@names);
	
	$self->SUPER::initialize();
}

sub finalize {
	my ($self) = @_;
	Fink::PkgVersion::phase_activate($self->{remove});
}

=back

=cut

1;
