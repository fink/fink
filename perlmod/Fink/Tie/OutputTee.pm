# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Tie::OutputTee class
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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA	 02111-1307, USA.
#

package Fink::Tie::OutputTee;

require Tie::Handle;
our @ISA = qw/ Tie::StdHandle /;

use strict;

=head1 NAME

Fink::Tie::OutputTee - a 'tee'ed tied-filehandle

=head1 SYNOPSIS

	use Fink::Tie::OutputTee;
	Fink::Tie::OutputTee->tee_start(*STDOUT, $filename);
	print "testing 1 2 3\n";
	Fink::Tie::OutputTee->tee_stop(*STDOUT);

=head1 DESCRIPTION

Fink::Tie::OutputTee is a tied filehandle for redirecting output into
multiple places at once.

=head2 Methods

This class is a subclass of Tie::StdHandle. The following methods
override those in that superclass:

=over 4

=item TIEHANDLE

	tie NEW_FH, "Fink::Tie::OutputTee", $old_fh, $filename;

Returns a writable filehandle bound to a newly-created Fink::Tie::OutputTee
object. The filehandle $old_fh must already be opened for writing. The
file $filename is opened for writing. A dup of $old_fh is saved before
NEW_FH is bound: if NEW_FH is $old_fh, one gets a Unixish "tee", not
endless recursion.

=cut

sub TIEHANDLE {
	my $class = shift;
	my $old_fh = shift;
	my $filename = shift;

	my $old_fileno = fileno($old_fh);

	open my $fh_dup, ">&$old_fileno" or die "Couldn't dup $old_fh: $!\n";
	open my $fh_log, '>>', $filename or die "Couldn't open $filename: $!\n";
	my $self = bless { filehandles => [ $fh_dup, $fh_log ] }, $class;
	return $self;
}

=item WRITE

	$tied_OutputTee->WRITE($string, $bytes);

This method implements the "write" function for the tied filehandle.
Text is written to $old_fh and written to $filename (as defined during
the tie: see the TIEHANDLE method and tee_start function).

=cut

sub WRITE {
	my $self = shift;
	foreach (@{$self->{filehandles}}) {
		Tie::StdHandle::WRITE($_,@_);
	}
}

=back

=head2 Functions

Several utility functions and class methods are available. These are
the usual interface for the package, though you're welcome to use the
underlying tie()able class.

=over 4

=item tee_start

	Fink::Tie::OutputTee->tee_start(*$filehandle, $filename);

Wrapper for TIEHANDLE that starts tee'ing the existing open and
writable $filehandle to the file $filename (appended if it already
exists).  You must pass $filehandle as a typeglob (*STDOUT or
*$lexical_fh).

=cut

sub tee_start {
	my $class = shift;
	my $filehandle = shift;
	my $filename = shift;

	tie $filehandle, $class, $filehandle, $filename;
}

=item tee_stop

	Fink::Tie::OutputTee->tee_stop($filehandle);

Stops tee'ing the $filehandle (as was passed to tee_start).

=cut

sub tee_stop {
	my $class = shift;
	my $fh = shift;
	untie $fh;
}

=back

=cut

1;
