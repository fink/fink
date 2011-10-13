# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Checksum::MD5 module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2005-2011 The Fink Package Manager Team
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

package Fink::Checksum::MD5;

use Fink::Checksum;
use Fink::Config qw($basepath);

our @ISA = qw(Fink::Checksum);
our $VERSION = 1.00;

our $md5cmd;
our $md5pm;
our $match;

sub about {
	my $self = shift;

	my @about = ('MD5', $VERSION, 'MD5 checksum');
	return wantarray? @about : \@about;
}

sub new {
	my $class = shift;

	my $self = bless({}, $class);

	eval "require Digest::MD5";
	if (!$@) {
		$md5pm = 1;
	} else {
		if(-e "/sbin/md5") {
			$md5cmd = "/sbin/md5";
			$match = '= ([^\s]+)$';
		} elsif (-e "$basepath/bin/md5deep") {
			$md5cmd = "$basepath/bin/md5deep";
			$match = '([^\s]*)\s*(:?[^\s]*)';
		} else {
			$md5cmd = "md5sum";
			$match = '([^\s]*)\s*(:?[^\s]*)';
		}
	}

	return ($md5pm || $md5cmd) ? $self : undef;
}

# Returns the MD5 checksum of the given $filename. Uses /sbin/md5 if it
# is available, otherwise uses the first md5sum in PATH. The output of
# the chosen command is read via an open() pipe and matched against the
# appropriate regexp. If the command returns failure or its output was
# not in the expected format, the program dies with an error message.

sub get_checksum {
	my $class = shift;
	my $filename = shift;

	my ($pid, $checksum);

	if ($md5pm) {
		my $md5 = Digest::MD5->new();
		open (FILEIN, $filename) or die "unable to read from $filename: $!\n";
		$md5->addfile(*FILEIN);
		$checksum = $md5->hexdigest;
		close(FILEIN) or die "Error closing $filename: $!\n";
	} else {
		$pid = open(MD5SUM, "$md5cmd $filename |") or die "Couldn't run $md5cmd: $!\n";
		while (<MD5SUM>) {
			if (/$match/) {
				$checksum = $1;
			}
		}
		close(MD5SUM) or die "Error on closing pipe  $md5cmd: $!\n";
	}

	if (not defined $checksum) {
		die "Could not parse results of '$md5cmd $filename'\n";
	}

	return lc($checksum);
}

1;
