# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Checksum::SHA1 module
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

package Fink::Checksum::SHA1;

use Fink::Checksum;
use Fink::Config qw($basepath);

our @ISA = qw(Fink::Checksum);
our $VERSION = 1.00;

our $sha1cmd;
our $sha1pm;
our $match;

sub about {
	my $self = shift;

	my @about = ('SHA1', $VERSION, 'SHA1 checksum', [ 'textutils', 'md5deep' ] );
	return wantarray? @about : \@about;
}

sub new {
	my $class = shift;

	my $self = bless({}, $class);

	$match = '(\S*)\s*(:?\S*)';

	eval "require Digest::SHA1";
	if (not defined $@) {
		$sha1pm = 1;
	} else {
		if (-x "$basepath/bin/sha1deep") {
			$sha1cmd = "$basepath/bin/sha1deep";
		} elsif (-x "/usr/bin/openssl") {
			$sha1cmd = '/usr/bin/openssl sha1';
			$match   = 'SHA1\([^\)]+\)\s*=\s*(\S+)';
		} elsif (-e "$basepath/bin/sha1sum") {
			$sha1cmd = "$basepath/bin/sha1sum";
		}
	}

	return ($sha1pm || $sha1cmd) ? $self : undef;
}

# Returns the SHA1 checksum of the given $filename. Uses $basepath/bin/sha1deep
# if it is available, otherwise uses uses $basepath/bin/sha1sum. The output of
# the chosen command is read via an open() pipe and matched against the
# appropriate regexp. If the command returns failure or its output was
# not in the expected format, the program dies with an error message.

sub get_checksum {
	my $class = shift;
	my $filename = shift;

	my ($pid, $checksum);

	if ($sha1pm) {
		my $sha1 = Digest::SHA1->new();
		open (FILEIN, $filename) or die "unable to read from $filename: $!\n";
		$sha1->addfile(*FILEIN);
		$checksum = $sha1->hexdigest;
		close(FILEIN) or die "Error closing $filename: $!\n";
	} else {
		$pid = open(SHA1SUM, "$sha1cmd $filename |") or die "Couldn't run $sha1cmd: $!\n";
		while (<SHA1SUM>) {
			if (/$match/) {
				$checksum = $1;
			}
		}
		close(SHA1SUM) or die "Error on closing pipe: $sha1cmd: $!\n";
	}

	if (not defined $checksum) {
		die "Could not get sha1 digest of $filename\n";
	}

	return lc($checksum);
}

1;
