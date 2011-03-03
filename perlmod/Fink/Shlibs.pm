# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Shlibs class
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

package Fink::Shlibs;

use Fink::Base;
use Fink::Services qw(&version_cmp);
use Fink::CLI qw(&print_breaking_stderr);
use Fink::Config qw($basepath);
use Fink::PkgVersion;
use File::Find;

use strict;
use warnings;


BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	= 1.00;
	@ISA		= qw(Exporter Fink::Base);
	@EXPORT		= qw();
	@EXPORT_OK	= qw();
	%EXPORT_TAGS	= ( );
}
our @EXPORT_OK;

# The cached shlibs information, set to undef if not valid
our $shlibs = undef;

END { }				# module clean-up code here (global destructor)


=head1 NAME

Fink::Shlibs - Find dependencies based on shared libs.

=head1 SYNOPSIS

  # Get the dependencies for the files to be installed
  my @deps = Fink::Shlibs->get_shlibs $pkgname, @files;

  # Invalidate the current internal cache of shlibs when dpkg changes
  Fink::Shlibs->invalidate;

=head1 DESCRIPTION

Most of the dependencies needed for a package to be installed are simply to
supply the shared libraries which it links to. Because each package which
supplies a shared library lists it in the 'Shlibs' field, these dependencies
can be determined automatically.

=head1 FUNCTIONS

=over 4

=item get_shlibs

  my @depspecs = Fink::Shlibs->get_shlibs $pv, @files;

Get the dependency specifications needed to supply the shared libs linked to
by the given files.

Pass in the PkgVersion object for which we are getting the depends, and
the list of files which should be checked.

A dependency specification is a package name and a version specification,
eg: 'foo (>= 1.0-1)'.

=cut

sub get_shlibs {
	my ($class, $pv, @filelist) = @_;

	my @depends = $class->_check_files($pv, @filelist);
	
	my %found; # don't duplicate
	foreach my $depend (@depends) {
		if (length($depend) > 1) {
			$found{$depend} = 1;
		}
	}

	return sort keys %found;
}

=item invalidate

  Fink::Shlibs->invalidate;

When the state of dpkg changes (ie: when a package is installed or removed),
the cache of installed shlibs needs to be regenerated. This function notifies
Shlibs when this is the case.

=back

=cut

sub invalidate {
	$shlibs = undef;
}

=begin private

  my @depspecs = Fink::Shlibs->_check_files $pv, @filelist;

Similar to get_shlibs, but unchecked output, so depspecs may be empty or
duplicate.

=end private

=cut

sub _check_files {
	my ($self, $pkg, @files) = @_;
	
	my ($file, @depends, $deb, $currentlib, $lib, $compat);
	my (@splits, $split, $tmpdep, $dep, $vers, @dsplits, $dsplit);
	my (@deplines, @builddeps, $depline, $builddep);

	# get parent and split names to envoke a = %v-%r override
	@splits = $pkg->get_splitoffs(1, 1);

	# Get runtimedepends and depends line and builddepends line for compares
	@deplines = split(/\s*\,\s*/, $pkg->pkglist_default("Depends", ""));
	push @deplines, split(/\s*\,\s*/, $pkg->pkglist_default("RunTimeDepends", ""));
	@builddeps = split(/\s*\,\s*/, $pkg->pkglist_default("BuildDepends", ""));

	# get a list of linked files to the pkg files
	FILELOOP: foreach $file (@files) {
		chomp($file);
		open(OTOOL, "otool -L $file 2>/dev/null |") or
				die "can't run otool: $!\n";
			# need to drop all links to system libs and the
			# first two lines
			OTOOLLOOP: while (<OTOOL>) {
				chomp();
				#drop first lines and errors
				if ($_ =~ /:/) {
					# not a lib, droping
					next OTOOLLOOP;
				}
				# Get lib
				unless ($_ =~ /^\s*(\S+)\s+\(\S+\s\S+\s(\d+\.\d+.\d+),.*$/) {
					# not matching REGEX
					next OTOOLLOOP;
				} else {
					$lib = $1;
					$compat = $2;
				}

				# Make sure it's a lib and is installed.
				# next unless (-x $lib);

				### This should drop any depends on it's self
				### Strictly on it's self not a child
				$deb = $self->_get_shlib($lib, $compat);
				unless ($deb) {
					# Add a big warning about /usr/local/lib being
					# in the way if $basepath isn't /usr/local
					if ($lib =~ /^\/usr\/local\/lib/ &&
					    !$basepath =~ /^\/usr\/local[\/]?$/) {
							die "There are files in /usr/local that will break fink, please move them out of the way and rebuild this package.\n";
					}

					# no package found for shlib file
					next OTOOLLOOP;
				}
				
				# get just the unversioned dep for compares
				$tmpdep = $deb;
				$tmpdep =~ s/^(\S*)\s*\(.*\)$/$1/g;

				if ($tmpdep eq $pkg->get_name) {
					next OTOOLLOOP;
				}

				### Checking for dep on own shlibs
				### force to =%v-%r
				foreach $split (@splits) {
					# FIXME
					# get just the unversioned dep
					# this won't work until the splits are
					# installed, need to check the shlibs
					# in the root and splitoff roots at this
					# point
					if ($split eq $tmpdep) {
						# should force =%v-%r once working
					}
				}

				### Check that a dep isn't already explicitly
				### set
				foreach $depline (@deplines) {
					if ($depline =~ /^(\S*)\s*\((.*)\)$/) {
						$vers = $2;
						$dep = $1;
					} else {
						$vers = "";
						$dep = $depline;
					}
					if ($dep eq $tmpdep) {
						next OTOOLLOOP;
					}
				}

				### Build dep versions override shlibs files
				foreach $builddep (@builddeps) {
					### Need to check splits here.
					if ($builddep =~ /^(\S*)\s*\((.*)\)$/) {
						$vers = $2;
						$dep = $1;
					} else {
						# no need to continue if	
						# no version
						next;
					}
					# check all splits of the deps to find
					# this shlibs version of the -dev
					my $deppkg = Fink::PkgVersion->match_package($dep);
					unless (defined $deppkg) {
						print STDERR "no package found for specification '$dep'!\n";
						next;
					}

					@dsplits = $deppkg->get_splitoffs(1, 1);
					foreach $dsplit (@dsplits) {
						if ($dsplit eq $tmpdep) {
							# override version based on specified Depends
							$deb = $dsplit." (".$vers.")";
							push(@depends, $deb)
						}
					}
				}

				push(@depends, $deb) if (defined $deb and $deb !~ /^\s*$/);
			}
		close (OTOOL);
	}

	if (Fink::Config::get_option("maintainermode")) {
		print "- Depends before deduplication: ", join(', ', @depends), "\n";
	}

	# this next bit does some really strange voodoo, I will try to
	# explain how it works.

	# first, there is a hash that contains a list of <package>,<operator>
	# tuples -- we use this for determining if a package is mentioned
	# multiple times.  We need to consider <package>,<operator> as a
	# unique key rather than just the package name because of cases like:
	#
	#   Depends: macosx (>= 10.1), macosx (<< 10.4)

	my $depvers = {};

	# next, there is an array that keeps a cooked version of the input
	# dependency list, with "<package> (<operator> <version>)" transformed
	# into "<package>,<operator>" -- this retains the order, as well as
	# any combinations of foo|bar|baz and so on, for the purposes of
	# recreating it later.

	my @newdeps;

	# so, first we go through each depend, turn it into an object that
	# contains versioning information and such, and then fills in the
	# $depvers hash and @newdeps array.

	for my $dep (@depends) {
		my @depobj = _get_depobj($dep);
		my $name;

		# get_depobj() returns multiple entries when the source depend
		# is a foo|bar|baz style dependency (ie alternates)
		# for each one of these we want to strip it down to a
		# @newdeps-style value, and pump each of the individual deps
		# into the $depvers hash, then recreating the |'s with the
		# @newdeps values instead of the original package spec.

		if (@depobj == 0) {
			# empty, we skip it
			next;
		} elsif (@depobj > 1) {
			my @depnames;
			for my $obj (@depobj) {
				push(@depnames, $obj->{tuplename});
			}
			$name = join('|', @depnames);
			undef @depnames;
			for my $obj (@depobj) {
				$depvers = _update_version_hash($depvers, $obj);
			}
		} else {
			$name = $depobj[0]->{tuplename};
			$depvers = _update_version_hash($depvers, $depobj[0]);
		}

		next if (not defined $name);

		# this will skip putting something into @newdeps if it's
		# already there (it has to match the <package>,<operator>
		# tuple exactly, not just the package name, to be
		# considered a duplicate)

		if (not grep($_ eq $name, @newdeps)) {
			push(@newdeps, $name);
		}
	}

	@depends = ();

	# now, we parse through the cooked data, and generate a new
	# dependency list, with duplicates removed because of the
	# skip above, and any matching version comparisons for a given
	# package should all be in parity

	for my $depspec (@newdeps) {
		if ($depspec =~ /\|/) {

			# if it's a multiple, we chop it up and transform each
			# part into it's "real" comparison, and then put it back
			# together and stick it on the new @depends

			my @splitdeps = split(/\|/, $depspec);

			for my $index (0..$#splitdeps) {

				if (defined $depvers->{$splitdeps[$index]}->{operator}) {
					# operator is defined if there was a
					# version comparison
					$splitdeps[$index] = $depvers->{$splitdeps[$index]}->{name} . ' (' . $depvers->{$splitdeps[$index]}->{operator} . ' ' . $depvers->{$splitdeps[$index]}->{version} . ')';
				} else {
					$splitdeps[$index] = $depvers->{$splitdeps[$index]}->{name};
				}
			}
			push(@depends, join(' | ', @splitdeps));
		} else {
			# otherwise we just transform the single entry and push
			# it on the depends array

			if (defined $depvers->{$depspec}->{operator}) {
				# operator is defined if there was a
				# version comparison
				push(@depends, $depvers->{$depspec}->{name} . ' (' . $depvers->{$depspec}->{operator} . ' ' . $depvers->{$depspec}->{version} . ')');
			} else {
				push(@depends, $depvers->{$depspec}->{name});
			}
		}
	}

	if (Fink::Config::get_option("maintainermode")) {
		print "- Depends after deduplication: ", join(', ', @depends), "\n";
	}
	return @depends;
}

### this is a scary subroutine to update the name,operator cache
### for handling duplicates -- it's just plain evil.  EVIL.  EEEEVIIIILLLL.
sub _update_version_hash {
	my $hash   = shift;
	my $depobj = shift;

	if (exists $hash->{$depobj->{tuplename}}) {

		# if the name,operator pair exists in the dep cache hash
		if ($depobj->{operator} =~ /^==?$/ and
			$depobj->{version} ne
			$hash->{$depobj->{tuplename}}->{version}) {

			# can't have 2 different versions in an == comparison
			# for the same dependency
			# (ie, Depends: macosx = 10.2-1, macosx = 10.3-1)

			warn "this package depends on ", $depobj->{name}, " = ", $depobj->{version}, " *and* ", $depobj->{name}, " = ", $hash->{$depobj->{tuplename}}->{version}, "!!!\n";

		} elsif (version_cmp($depobj->{version}, $depobj->{operator}, $hash->{$depobj->{tuplename}}->{version})) {
			# according to the operator, this new dependency
			# is more "specific"
			$hash->{$depobj->{tuplename}} = $depobj;
		}
	} elsif (not defined $depobj->{operator}) {
		# $depobj contains an unversioned dependency, we have to
		# check if there's a more specific comparison already in
		# the dep cache

		my @matches = grep(/^$depobj->{name}\,/, keys %{$hash});

		if (@matches > 0) {
			# $depobj has no version dep, but a versioned
			# dependency already exists in the object cache
			# take the first match and use it instead of $depobj
			$hash->{$depobj->{tuplename}} = $hash->{$matches[0]};

			if (@matches > 1) {
				warn "more than one version comparison exists for ", $depobj->{name}, "!!!\n", "taking ", $hash->{$matches[0]}->{tuplename}, "\n";
			}
		} else {
			# $depobj isn't in the cache (versioned or not), just
			# put what we have in
			$hash->{$depobj->{tuplename}} = $depobj;
		}
	} elsif (grep(/^$depobj->{name}$/, keys %{$hash})) {
		# $depobj has a versioned dep, but an unversioned dependency
		# already exists in the object cache -- we need to update the
		# previous one

		$hash->{$depobj->{tuplename}} = $depobj;
		$hash->{$depobj->{name}}      = $depobj;
	} else {
		# if the tuple doesn't exist, we add it
		$hash->{$depobj->{tuplename}} = $depobj;
	}

	return $hash;
}

# get a dependency "object" (just a data structure with dep info)
sub _get_depobj {
	my $depdef = shift;
	my ($depobj, $name, $operator, $version);
	my @return;

	# this seems weird, but splitting when there isn't a "|" will
	# just give a 1-entry array, so it works even in the case there's
	# no multiple comparison (ie, "foo|bar")

	for my $dep (split(/\s*\|\s*/, $depdef)) {
		$dep =~ s/[\r\n\s]+/ /;
		$dep =~ s/^\s+//;
		$dep =~ s/\s+$//;
		if (($name, $operator, $version) = $dep =~ /^\s*(.+?)\s+\(([\<\>\=]+)\s+(\S+)\)\s*$/) {
			$depobj->{name}      = $name;
			$depobj->{operator}  = $operator;
			$depobj->{version}   = $version;
			$depobj->{tuplename} = $name . ',' . $operator;
		} else {
			$depobj->{name}      = $dep;
			$depobj->{operator}  = undef;
			$depobj->{version}   = '0-0';
			$depobj->{tuplename} = $dep;
		}
		push(@return, $depobj);
	}

	return @return;
}

### get package name
sub _get_shlib {
	my $self = shift;
	my $lib = shift;
	my $compat = shift;
	
	$self->_validate; # Ensure the cache exists
	
	my ($dep, $shlib, $count, $pkgnum, $vernum, $total);

	$dep = "";

	foreach $shlib (keys %$shlibs) {
		if ("$shlib" eq "$lib" && $shlibs->{$shlib}->{$compat}) {
			$total = $shlibs->{$shlib}->{$compat}->{total};
			for ($count = 1; $count <= $total; $count++) {
				$pkgnum = "package".$count;
				$vernum = "version".$count;
				$dep .= $shlibs->{$shlib}->{$compat}->{$pkgnum}." (".$shlibs->{$shlib}->{$compat}->{$vernum}.")";
				if ($count < $total) {
					$dep .= " | ";
 				}
			}
		}
	}

	return $dep;
}

=begin private

  Fink::Shlibs->_validate;

Ensure that the current shlib cache is valid.

=end private

=cut

sub _validate {
	my $class = shift;
	return if defined $shlibs; # Cache ok
	
	$class->_scan();
}

=begin private

  Fink::Shlibs->_scan;

Scan the shlibs files and generate the shlibs cache

=end private

=cut

sub _scan {
	my $class = shift;
	
	print_breaking_stderr "Scanning for shlibs...";
	
	# Where to look for .shlibs files?
	my $directory = "$basepath/var/lib/dpkg/info";
	return if not -d $directory;
	
	# Scan for .shlibs files
	my @filelist;
	find({
		wanted => sub {
			push @filelist, $_ if -f and not /^[\.\#]/ and /\.shlibs$/;
		},
		follow => 1, no_chdir => 1
	}, $directory);
	
	my ($shlibname, $compat, $package);

	foreach my $filename (@filelist) {
		open(SHLIB, $filename) or die "can't open $filename: $!\n";
			while(my $line = <SHLIB>) {
				chomp($line);
				$line =~ s/^\s*//;
				$line =~ s/\s*$//;
				if ($line =~ /^(.+)\s+([.0-9]+)\s+(.*)$/) {
					my $shlibname = $1;
					my $compat = $2;
					my $package = $3;

					unless ($shlibname) {
						print_breaking_stderr "WARNING: No lib name in $filename";
						next;
					}
					unless ($compat) {
						print_breaking_stderr "WARNING: No lib compatability version for $shlibname";
						next;
					}
					unless ($package) {
						print_breaking_stderr "WARNING: No owner package(s) for $shlibname";
						next;
					}

					$class->_inject_shlib($shlibname, $compat, $package);
				}
			}
		close(SHLIB);
	}
}

=begin private

  Fink::Shlibs->_inject_shlib $lib, $compat, $supplied_by;

Add a shared lib into the shlibs cache.

=end private

=cut

sub _inject_shlib {
	my $class = shift;
	my $shlibname = shift;
	my $compat = shift;
	my $package = shift;
	my (@packages, $pkg, $counter, $pkgnum, $vernum);

	if ($package =~ /\|/) {
		@packages = split(/\s*\|\s*/, $package);
		$counter = 0;
		foreach $pkg (@packages) {
			$counter++;
			if ($pkg =~ /(.+)\s+\((.+)\)/) {
				$pkgnum = "package".$counter;
				$vernum = "version".$counter;;
				$shlibs->{$shlibname}->{$compat}->{$pkgnum} = $1;
				$shlibs->{$shlibname}->{$compat}->{$vernum} = $2;
			}
			$shlibs->{$shlibname}->{$compat}->{total} = $counter;
		}
	} else {
		if ($package =~ /(.+)\s+\((.+)\)/) {
			$shlibs->{$shlibname}->{$compat}->{package1} = $1;
			$shlibs->{$shlibname}->{$compat}->{version1} = $2;
			$shlibs->{$shlibname}->{$compat}->{total} = 1;
		}
	}
}

### EOF
1;
# vim: ts=4 sw=4 noet
