#
# Fink::User class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2003 The Fink Package Manager Team
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

package Fink::User;

use Fink::Config qw($config $basepath $debarch);
use Fink::Services qw(&execute &print_breaking &prompt &prompt_boolean);
use User::grent;
use User::pwent;
use File::Find;
use Fcntl ':mode'; # for search_comparedb

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw(&get_perms &add_user &remove_user);
	%EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

our ($lowUID, $highUID, $lowGID, $highGID);

$lowUID = 250;
$highUID = 299;
$lowGID = 250;
$highGID = 299;

END { }				# module clean-up code here (global destructor)

### Get a list of uid:gid for all files in a pkg, this is per pkg not just
### parent pkgs, return a postinstscript to set them, include it in the deb
sub get_perms {
	my $self = shift;
	my $rootdir = shift;

	my $script = ""

	my (@filelist, @files, @users, @groups);
	my ($wanted, $file, $usr, $grp);
	my ($dev, $ino, $mode, $nlink, $uid, $gid);

	### Weird why isn't $rootdir the full path...odd
	unless ($rootdir =~ /^$basepath\/src/) {
		$rootdir = "$basepath/src/$rootdir";
	}

	$wanted =
		sub {
			if (-x) {
				push @filelist, $File::Find::fullname;
			}
		};
	find({ wanted => $wanted, follow => 1, no_chdir => 1 }, $rootdir);
    
	foreach $file (@filelist) {
		### Don't add DEBIAN dir
		next if ($file =~ /DEBIAN/);
		### Skip the rootdir
		next if ($file == $rootdir);
	  
		($dev, $ino, $mode, $nlink, $uid, $gid) = lstat($file);

		### Skip anything that doesn't have a user or group;
		next if (not $uid or not $gid);
	  
		$usr = User::pwent::getpwuid($uid);
		$grp = User::grent::getgrgid($gid);

		### Remove $basepath/src/root-...
		$file =~ s/^$rootdir//g;

		### DEBUG
		print "Processing $file...UID: $uid, GID: $gid\n";
	  
		push(@files, $file);
		push(@users, $usr);
		push(@groups, $grp);
	}

	$file = join(":", @files);
	$usr = join (":", @users);
	$grp = join (":", @groups);

	$self->set_perms($rootdir, $file);

	$script = $self->get_chown($file, $usr, $grp);

	return $script;
}

### add check/add user script and then set perms
sub add_user {
	my $self = shift;
	my $name = shift;
	my $type = shift;
	my $desc = shift;
	my $shell = shift || "/usr/bin/false";
	my $home = shift;
	my $group = shift || $name;
 
	my $nidump = "/usr/bin/nidump";
	my $niutil = "/usr/bin/niutil";
	my $grep = "/usr/bin/grep";
	my $cut = "/usr/bin/cut";
	my $chown = "/usr/sbin/chown";
	my $mkdir = "/bin/mkdir -p";
	my $expr = "/bin/expr";

	my $pass = "*";
	my $script = "";

	### FIXME need to figure a way here to get and set uids and gids, and
	### ask if the fink.conf specifies this.  maybe use a grep on fink.conf

	if ($type eq "user") {
		$script = <<"EOF";
getgid() {
  gid=`$nidump group . | $grep -e \"^$name:\" | $cut -d\":\" -f3`
}

getuid() {
  uid=`$nidump passwd . | $grep -e \"^$name:\" | $cut -d\":\" -f3`
  if [ ! \$uid ]; then
    continue="no"
    number_used="dontknow"
    fnumber=$lowUID
    until [ \$continue = "yes" ]; do
      if [ `$nidump passwd . | $cut -d":" -f3 | $grep -c "^\$fnumber$"` -gt 0 ]; then
        number_used=true
      else
        if [ \$fnumber -gt $highUID ]; then
          break
        fi
        number_used=false
      fi

      if [ \$number_used = "true" ]; then
        fnumber=`$expr \$fnumber + 1`
      else
        uid="\$fnumber"
        continue="yes"
      fi
    done;
  fi
}

uid=getuid()
gid=getgid()

if [ \$uid -gt $highUID ]; then
  exit 1
fi

if [ ! \$gid ]; then
  exit 1
fi

if [ \$uid -lt $lowUID ]; then
  exit 1
fi

$niutil -create . /users/$name
$niutil -createprop . /users/$name realname "$desc"
$niutil -createprop . /users/$name gid \$gid
$niutil -createprop . /users/$name uid \$uid
$niutil -createprop . /users/$name home "$home"
$niutil -createprop . /users/$name name "$name"
$niutil -createprop . /users/$name passwd "$pass"
$niutil -createprop . /users/$name shell "$shell"
$niutil -createprop . /users/$name change 0
$niutil -createprop . /users/$name expire 0
$mkdir "$home"
$chown $name:$group "$home"

EOF
	} else {
		$script = <<"EOF";
getgid() {
  gid=`$nidump group . | $grep -e \"^$name:\" | $cut -d\":\" -f3`
  if [ ! \$gid ]; then
    continue="no"
    number_used="dontknow"
    fnumber=$lowGID
    until [ \$continue = "yes" ]; do
      if [ `$nidump group . | $cut -d":" -f3 | $grep -c "^\$fnumber$"` -gt 0 ]; then
        number_used=true
      else
        if [ \$fnumber -gt $highGID ]; then
          break
        fi
        number_used=false
      fi

      if [ \$number_used = "true" ]; then
        fnumber=`$expr \$fnumber + 1`
      else
        gid="\$fnumber"
        continue="yes"
      fi
    done;
  fi
}

gid=getgid()

if [ \$gid -gt $highGID ]; then
  exit 1
fi

if [ \$gid -lt $lowGID ]; then
  exit 1
fi

$niutil -create . /groups/$name
$niutil -createprop . /groups/$name name "$name"
$niutil -createprop . /groups/$name gid \$gid
$niutil -createprop . /groups/$name passwd "$pass"

EOF
	}
    
	return $script;
}

### Check remove user/group
sub remove_user {
	my $self = shift;
	my $name = shift;
	my $type = shift;

	my $nidump = "/usr/bin/nidump";
	my $niutil = "/usr/bin/niutil";
	my $grep = "/usr/bin/grep";
	my $cut = "/usr/bin/cut";
	my $rm = "/bin/rm -rf";

	my $script = "";
    
	if ($type eq "user") {
		$script = <<"EOF";
HomeDir=`$nidump passwd . | $grep '$name:' | $cut -d\":\" -f9`
$rm \$HomeDir
$niutil -destroy . /users/$name

EOF
	} else {
		$script = <<"EOF";
$niutil -destroy . /groups/$name

EOF
	}
    
	return $script
}

### build script to set user/groups
sub get_chown {
	my $self = shift;
	my $files = shift;
	my $users = shift;
	my $groups = shift;

	my ($file);
	my $script = "";
	my $i = 0;
	
	### Build perms script
	my @files = split(/:/, $files);
	my @users = split(/:/, $users);
	my @groups = split(/:/, $groups);

	foreach $file (@files) {
		$script .= "/usr/sbin/chown $users[$i]:$groups[$i] \"$file\"\n";
		$i++;
	}
    
	return $script;
}

### Set everything to root:wheel before packaging to keep all debs the same
sub set_perms {
	my $self = shift;
	my $rootdir = shift;
	my $files = shift;
	
	my ($file);
	my @files = split(/:/, $files);
	
	foreach $file (@files) {
		if (&execute("/usr/sbin/chown root:wheel \"$rootdir$file\"")) {
			die "Couldn't change ownership of $file!\n";
		}
	}

	return 0;
}

### EOF
1;
