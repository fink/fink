# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Finally::Buildlock module
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

package Fink::Finally::Buildlock;
use base 'Fink::Finally';

use warnings;
use strict;

use POSIX	qw(strftime);

use Fink::Command	qw(mkdir_p rm_rf rm_f);
use Fink::Config	qw($basepath $config $buildpath);
use Fink::CLI qw(&print_breaking &rejoin_text);
use Fink::PkgVersion;

use Fink::Services	qw(	lock_wait lol2pkglist execute dpkg_lockwait
						apt_available	);

=head1 NAME

Fink::Finally::Buildlock - Ensure that builds don't interfere.

=head1 DESCRIPTION

Buildlocks are designed to prevent concurrent fink processes from interfering with each other's dependencies.

For example, if one fink process is compiling a package "foo" that has a build-time dependency on the package "bar-dev", that fink process will set a build-lock that prevents another fink (or dpkg or apt or...) from removing the bar-dev package until the first fink process finishes building the package foo. In addition, buildlocks prevent concurrent builds of any given package (name-version-revision) to prevent the build processes from over-writing each other's files.

See L<http://wiki.finkproject.org/index.php/Fink:buildlocks> for more
information.

=head1 CLASS METHODS

=over 4

=item new

  my $bl = Fink::Finally::Buildlock->new($pv);

Put a buildlock on the Fink::PkgVersion object I<$pv>. The lock will be
removed when I<$bl> goes out of scope.

=cut

# create an exclusive lock for the %f of the parent using dpkg
sub initialize {
	my ($self, $pv) = @_;
	
	# allow over-ride
	return if Fink::Config::get_option("no_buildlock");

	# lock on parent pkg
	$pv = $pv->get_parent if $pv->has_parent;
	$self->{_pv} = $pv;
	
	# bootstrapping occurs before we have package-management tools
	# needed for buildlocking. If you're bootstrapping into a location
	# that already has a running fink, you already know you're gonne
	# hose whatever may be running under that fink...
	return if $pv->is_bootstrapping;

	# The plan: get an exlusive lock for %n-%v-%r_$timestamp that
	# automatically goes away when this fink process quit. Install a
	# %n-%v-%r package that prohibits removal of itself if that lock
	# is present.  It's always safe to attempt to remove all installed
	# buildlock pkgs since they can each determine if these locks are
	# dead.  Attempting to install a lockpkg for the same %n-%v-%r
	# will cause existing one to attempt to be removed, which will
	# fail iff its lock is still alive. Fallback to the newer pkg's
	# prerm is okay because that will also be blocked by its own live
	# lock.

	print "Setting runtime build-lock...\n";

	my $lockdir = "$basepath/var/run/fink/buildlock";
	mkdir_p $lockdir or
		die "can't create $lockdir directory for buildlocks\n";

	my $timestamp = strftime "%Y.%m.%d-%H.%M.%S", localtime;
	my $lockfile = $self->{_lockfile} = $lockdir . '/' . $pv->get_fullname()
		. "_$timestamp.lock";
	my $lock_FH = $self->{_lock_fh} = lock_wait($lockfile, exclusive => 1);

	my $pkgname = $pv->get_name();
	my $pkgvers = $pv->get_fullversion();
	my $lockpkg = $self->{_lockpkg} = 'fink-buildlock-' . $pv->get_fullname();

	my $destdir = Fink::PkgVersion->get_install_directory($lockpkg);

	if (not -d "$destdir/DEBIAN") {
		mkdir_p "$destdir/DEBIAN" or
			die "can't create directory for control files for package $lockpkg\n";
	}

	# generate dpkg "control" file

	my $debarch = $config->param('Debarch');
	my $control = <<EOF;
Package: $lockpkg
Source: fink
Version: $timestamp
Section: unknown
Installed-Size: 0
Architecture: $debarch
Description: Package compile-time lockfile
 This package represents the compile-time dependencies of a
 package being compiled by fink. The package being compiled is:
   $pkgname ($pkgvers)
 and the build process begun at $timestamp
 .
 Web site: http://wiki.finkproject.org/index.php/Fink:buildlocks
 .
 Maintainer: Fink Core Group <fink-core\@lists.sourceforge.net>
Maintainer: Fink Core Group <fink-core\@lists.sourceforge.net>
Provides: fink-buildlock
EOF

	# buildtime (anti)dependencies of pkg are runtime (anti)dependencies of lockpkg
	my $depfield;
	$depfield = &lol2pkglist($pv->get_depends(1, 1));
	if (length $depfield) {
		$control .= "Conflicts: $depfield\n";
	}
	$depfield = &lol2pkglist($pv->get_depends(1, 0));
	if (length $depfield) {
		$control .= "Depends: $depfield\n";
	}

	### write "control" file
	if (open my $controlfh, '>', "$destdir/DEBIAN/control") {
		print $controlfh $control;
		close $controlfh or die "can't write control file for $lockpkg: $!\n";
	} else {
		die "can't write control file for $lockpkg: $!\n";
	}

	### set up the lockfile interlocking

	# this is implemented in perl but PreRm is in bash so we gonna in-line it
	my $prerm = <<EOF;
#!/bin/bash -e

if [ failed-upgrade = "\$1" ]; then
  exit 1
fi

if /usr/bin/perl -e 'exit 0 unless eval { require Fink::Finally::Buildlock }; \\
	exit !Fink::Finally::Buildlock->can_remove("$lockfile")'; then
  rm -f $lockfile
  exit 0
else
  cat <<EOMSG
There is currently an active buildlock for the package
     $pkgname ($pkgvers)
meaning some other fink process is currently building it.
EOMSG
  exit 1
fi
EOF

	### write prerm file
	if (open my $prermfh, '>', "$destdir/DEBIAN/prerm") {
		print $prermfh $prerm;
		close $prermfh or die "can't write PreRm file for $lockpkg: $!\n";
		chmod 0755, "$destdir/DEBIAN/prerm";
	} else {
		die "can't write PreRm file for $lockpkg: $!\n";
	}

	### store our PID in a file in the buildlock package
	my $deb_piddir = "$destdir$lockdir";
	if (not -d $deb_piddir) {
		mkdir_p $deb_piddir or
			die "can't create directory for lockfile for package $lockpkg\n";
	}
	if (open my $lockfh, ">$deb_piddir/" . $pv->get_fullname() . ".pid") {
		print $lockfh $$,"\n";
		close $lockfh or die "can't create pid file for package $lockpkg: $!\n";
	} else {
		die "can't create pid file for package $lockpkg: $!\n";
	}

	### create .deb using dpkg-deb (in buildpath so apt doesn't see it)
	if (&execute("dpkg-deb -b $destdir $buildpath")) {
		die "can't create package $lockpkg\n";
	}
	rm_rf $destdir or
		&print_breaking("WARNING: Can't remove package root directory ".
						"$destdir. ".
						"This is not fatal, but you may want to remove ".
						"the directory manually to save disk space. ".
						"Continuing with normal procedure.");

	# install lockpkg (== set dpkg lock on our deps)
	print "Installing build-lock package...\n";
	my $debfile = $buildpath.'/'.$lockpkg.'_'.$timestamp.'_'.$config->param('Debarch').'.deb';
	my $lock_failed = &execute(dpkg_lockwait() . " -i $debfile", ignore_INT=>1);
	Fink::PkgVersion->dpkg_changed;

	if ($lock_failed) {
		print_breaking rejoin_text <<EOMSG;
Can't set build lock for $pkgname ($pkgvers)

If any of the above dpkg error messages mention conflicting packages or
missing dependencies -- for example, telling you that the package
fink-buildlock-$pkgname-$pkgvers
conflicts with something else -- fink has probably gotten confused by trying 
to build many packages at once. Try building just this current package
$pkgname (i.e, "fink build $pkgname"). When that has completed successfully, 
you could retry whatever you did that led to the present error.

Regardless of the cause of the lock failure, don't worry: you have not
wasted compiling time! Packages that had been completely built before
this error occurred will not have to be recompiled.

See http://wiki.finkproject.org/index.php/Fink:buildlocks for more information.
EOMSG

		# Failure due to dependency problems leaves lockpkg in an
		# "unpacked" state, so try to remove it entirely.
		unlink $lockfile;
		close $lock_FH;
		&execute(dpkg_lockwait() . " -r $lockpkg >/dev/null", ignore_INT=>1);
	}

	# Even if installation fails, no reason to keep this around
	rm_f $debfile or
		&print_breaking("WARNING: Can't remove binary package file ".
						"$debfile. ".
						"This is not fatal, but you may want to remove ".
						"the file manually to save disk space. ".
						"Continuing with normal procedure.");

	die "buildlock failure\n" if $lock_failed;

	# prime for cleanup
	$self->SUPER::initialize();
}

sub finalize {
	my ($self) = @_;
	$self->SUPER::finalize();
	
	# we were locked...
	print "Removing runtime build-lock...\n";
	close $self->{_lock_fh};

	print "Removing build-lock package...\n";
	my $lockpkg = $self->{_lockpkg};

	# lockpkg's prerm deletes the lockfile
	if (&execute(dpkg_lockwait() . " -r $lockpkg", ignore_INT=>1)) {
		&print_breaking("WARNING: Can't remove package ".
						"$lockpkg. ".
						"This is not fatal, but you may want to remove ".
						"the package manually as it may interfere with ".
						"further fink operations. ".
						"Continuing with normal procedure.");
	}
	Fink::PkgVersion->dpkg_changed;	
}

=item can_remove

  my $fh = Fink::Finally::Buildlock->can_remove($lockfile);

Test if it is safe to remove a buildlock for a given lock-file.
After calling this, the caller must either close I<$fh> or delete the
lockfile.

=cut

sub can_remove {
	my ($class, $lockfile) = @_;
	return lock_wait("$lockfile", exclusive => 1, no_block => 1);
}

=back

=cut

1;
