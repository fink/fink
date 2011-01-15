# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Status class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2011 The Fink Package Manager Team
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

package Fink::Status;

use Fink::Config qw($config $basepath);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw();	# eg: qw($Var1 %Hashit &func3);
	%EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

my $the_instance = undef;

END { }				# module clean-up code here (global destructor)


### constructor

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $self = {};
	bless($self, $class);

	$self->initialize();

	$the_instance = $self;
	return $self;
}

### self-initialization

sub initialize {
	my $self = shift;
	my ($hash);
	$self->read();
}

### read dpkg's status file

sub read {
	my $self = shift;
	my ($file, $hash);

	$file = $basepath."/var/lib/dpkg/status";
	$hash = {};

	if ($config->mixed_arch() or not $config->want_magic_tree('status')) {
		return;
	}

	if (! -f $file) {
		print "WARNING: can't read dpkg status file \"$file\".\n";
		return;
	}

	open(IN,$file) or die "can't open $file: $!";

	# store info about the db file we're caching
	# (dpkg writes to a tempfile, then renames it to replace old)
	($self->{_db_ino}, $self->{_db_mtime}) = (stat IN)[1,9];

	while (<IN>) {
		chomp;
		if (/^([0-9A-Za-z_.\-]+)\:\s*(\S.*?)\s*$/) {
			$hash->{lc $1} = $2;
		} elsif (/^\s*$/) {
			# line of just whitespace separates packages entries in the file
			if (exists $hash->{package}) {
				$self->{$hash->{package}} = $hash;
			}
			$hash = {};
		}
		# we don't care about continuation lines
	}
	close(IN);

	# handle last pkg entry in file (maybe no whitespace line after it)
	if (exists $hash->{package}) {
		$self->{$hash->{package}} = $hash;
	}
}

### update cached data if db file on disk has changed

sub validate {
	my $self = shift;

	return if $self->is_reload_disabled();

	my(@db_stat) = stat $basepath.'/var/lib/dpkg/status';
	unless (
		@db_stat
		and (($self->{_db_ino}   || 0) == $db_stat[1])
		and (($self->{_db_mtime} || 0) == $db_stat[9])
	) {
		$self->read();
	}
}

### query by package name
# returns false when not installed
# returns full version when installed and configured

sub query_package {
	my $self = shift;
	my $pkgname = shift;
	my ($hash);

	if (not ref($self)) {
		if (defined($the_instance)) {
			$self = $the_instance;
		} else {
			$self = Fink::Status->new();
		}
	}

	$self->validate();

	if (exists $self->{$pkgname} and $self->{$pkgname}->{status} =~ /\s+installed$/i) {
		return $self->{$pkgname}->{version};
	}
	return undef;
}

### retrieve whole list with versions
# doesn't care about installed status
# returns a hash ref, key: package name, value: hash with core fields
# in the hash, 'package' and 'version' are guaranteed to exist

sub list {
	my $self = shift;
	my ($list, $pkgname, $hash, $newhash, $field);

	if (not ref($self)) {
		if (defined($the_instance)) {
			$self = $the_instance;
		} else {
			$self = Fink::Status->new();
		}
	}

	$self->validate();

	$list = {};
	foreach $pkgname (keys %$self) {
		next if $pkgname =~ /^_/;
		$hash = $self->{$pkgname};
		next unless exists $hash->{version};

		$newhash = { 'package' => $pkgname,
								 'version' => $hash->{version} };
		foreach $field (qw(depends provides conflicts maintainer description)) {
			if (exists $hash->{$field}) {
				$newhash->{$field} = $hash->{$field};
			}
		}
		$list->{$pkgname} = $newhash;
	}

	return $list;
}

{
	my $reload_disabled = 0;

# The logical value of the argument of this class method controls
# whether we should bother checking whether the dpkg status file has
# changed on disk. If false (default), we check every time we use our
# local copy of the data read from it. If true, we always use the data
# we previously read, even if it is stale. This mode should not be
# left in a set state...only set it temporarily in loops and unset as
# soon as done.
	sub disable_reload {
		my $class = shift;
		my $action = shift;

		$reload_disabled = ( $action ? 1 : 0 );
	}

# query the reload_disabled setting
	sub is_reload_disabled {
		my $class = shift;

		return $reload_disabled;
	}
}


### EOF
1;
# vim: ts=4 sw=4 noet
