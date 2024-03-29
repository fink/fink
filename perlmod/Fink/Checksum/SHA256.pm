# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Checksum::SHA256 module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2005-2018 The Fink Package Manager Team
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

package Fink::Checksum::SHA256;

use Fink::Checksum;
use Fink::Config qw($basepath);

our @ISA = qw(Fink::Checksum);
our $VERSION = 1.00;

our $sha256cmd;
our $match;

sub about {
	my $self = shift;

	my @about = ('SHA256', $VERSION, 'SHA256 checksum', [ 'md5deep' ] );
	return wantarray? @about : \@about;
}

sub new {
	my $class = shift;

	my $self = bless({}, $class);

	$match = '(\S*)\s*(:?\S*)';

	if (!defined($basepath)) {
		$basepath = "";
	}

	# external commands definitely needed (especially
	# apple-supplied) because no perl implementation
	if (-x "$basepath/bin/sha256deep") {
		$sha256cmd = "$basepath/bin/sha256deep";
	} elsif (-x "/usr/bin/openssl") {
		$sha256cmd = '/usr/bin/openssl dgst -sha256';
		$match     = 'SHA256\([^\)]+\)\s*=\s*(\S+)';
	} elsif (-x "$basepath/bin/openssl") {
		$sha256cmd = '$basepath/bin/openssl dgst -sha256';
		$match     = 'SHA256\([^\)]+\)\s*=\s*(\S+)';
	} elsif (-x "$basepath/lib/coreutils/bin/sha256sum") {
		$sha256cmd = "$basepath/lib/coreutils/bin/sha256sum";
	} elsif (-x "/usr/bin/shasum") {
		$sha256cmd = "/usr/bin/shasum -a 256 -b";
	}

	if (!defined $sha256cmd) {
		die "unable to find sha256 implementation. Try installing md5deep or coreutils\n";
	}

	return $self;
}

# Returns the SHA256 checksum of the given $filename.
# Uses a piped command (with output
# parsed against a regexp tailored to the specific command). If the
# command returns failure or its output was not in the expected
# format, the program dies with an error message.

sub get_checksum {
	my $class = shift;
	my $filename = shift;

	my ($pid, $checksum);

	$pid = open(SHA256SUM, "$sha256cmd $filename |") or die "Couldn't run $sha256cmd: $!\n";
	while (<SHA256SUM>) {
		if (/$match/) {
			$checksum = $1;
		}
	}
	close(SHA256SUM) or die "Error on closing pipe  $sha256cmd: $!\n";

	if (not defined $checksum) {
		die "Could not parse results of '$sha256cmd $filename'\n";
	}

	return lc($checksum);
}

1;
