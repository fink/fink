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
	@EXPORT_OK	 = qw(&get_perms &add_user_script &remove_user_script);
	%EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

our ($lowUID, $highUID, $lowGID, $highGID);

$lowUID = $config->param("lowUID") || 250;
$highUID = $config->param("highUID") || 299;
$lowGID = $config->param("lowGID") || 250;
$highGID = $config->param("highGID") || 299;

END { }				# module clean-up code here (global destructor)

### Using shell scripts for now, will just add the commands
### direct before finished, just faster for now

### Create User
sub add_user {
	my $self = shift;
	my $user = shift;
	my $desc = shift;
	my $pass = shift;
	my $shell = shift;
	my $home = shift;
	my $group = shift;

	my $uid = $self->get_id("user", $user);

	my $cmd  = "$basepath/sbin/useradd -c $desc -d $home -e 0";
	   $cmd .= "-f 0 -g $group -s $shell -u $uid $user";

	if (&execute($cmd)) {
		die "Can't create user '$user'\n";
	}

	return 0;
}

### Remove User
sub del_user {
	my $self = shift
	my $user = shift;

	my $cmd = "$basepath/sbin/userdel -r $user";

	if (&execute($cmd)) {
		die "Can't remove user '$user'\n";
	}

	return 0;
}

### Create Group
sub add_group {
	my $self = shift;
	my $group = shift;
	my $desc = shift;
	my $pass = shift;

	my $gid = $self->get_id("group", $group);

	my $cmd = "$basepath/sbin/groupadd -g $gid $group";

	if (&execute($cmd)) {
		die "Can't create group '$group'\n";
	}

	return 0;
}

### Remove Group
sub del_group {
	my $self = shift;
	my $group = shift;

	my $cmd = "$basepath/sbin/groupdel $group";

	if (&execute($cmd)) {
		die "Can't remove group '$group'\n";
	}

	return 0;
}

### Get uid or gid
sub get_id {
	my $self = shift;
	my $type = shift;
	my $name = shift;
	my $id = 0;		### set to 0 so first value is false

	### ask for uid or gid via type
	while (not $self->is_id_free($type, $id) {
		$id = $self->get_next_avail($type);
		if ($config->param_boolean("AskForID")) {
			if ($type eq "group") {
				$id = &prompt("Please enter a GID for $name ".
			              "[$lowGID...$highGID] ", $id);
			} else {
				$id = &prompt("Please enter a UID for $name ".
			              "[$lowUID...$highUID] ", $id);
			}
		}
	}

	return $id;
}

### Check if id is available (return 1 id available)
sub is_id_free {
	my $self = shift;
	my $type = shift;
	my $id = shift;
	my ($name);

	if ($type eq "user") {
		while ($name = User::pwent::getpwuid($id)) {
			return 1 if not $name;
		}
	} else {
		while ($name = User::grent::getgrgid($id)) {
			return 1 if not $name;
		}
	}

	return 0;
}

### check is a user or group exists before adding a user or group
sub check_for_name {
	my $self = shift;
	my $type = shift;
	my $name = shift;
	my $desc = shift;
	my $pass = shift || "";
	my $shell = shift || "/usr/bin/false";
	my $home = shift || "/tmp";
	my $group = shift || $name;
	my $id = 0;

	### find if a user exists
	while ($name not $currentname) {
		$id++;
		if ($type eq "group") {
			$currentname = User::grent::getgrgid($id);
			if ($name eq $currentname) {
                ### FIXME
                ### Compare info make it's hte same, or setup process rules
				return 1;
			}
		} else {
			$currentname = User::pwent::getpwuid($id);
			if ($name eq $currentname) {
                ### FIXME
                ### Compare info make it's hte same, or setup process rules
				return 1;
			}
		}
	}

	return 0;
}

### Get next available id
sub get_next_avail {
	my $self = shift;
	my $type = shift;
	my ($id, $user, $uid, $group, $gid, $pass);

	if ($type eq "user") {
		while (($user,$pass,$uid) = User::pwent::getpwent) {
			next if ($uid < $lowUID) || ($uid > $highUID);
			$id++;

			break if not $user;
		}
	} else {
		while (($group,$pass,$gid) = User::grent::getgrent) {
			next if ($gid < $lowGID) || ($gid > $highGID);
			$id++;

			break if not $group;
	}

	return $id;
}

### Get a list of uid:gid for all files in a pkg, this is per pkg not just
### parent pkgs, return a postinstscript to set them, include it in the deb
sub get_perms {
	my $self = shift;
	my $rootdir = shift;
	my $script = "";

	my (@filelist, @files, @users, @groups);
	my ($wanted, $file, $usr, $grp);
	my ($dev, $ino, $mode, $nlink, $uid, $gid);
    
	$wanted =
		sub {
			if (-x) {
				push @filelist, $File::Find::fullname;
			}
		};
	find({ wanted => $wanted, follow => 1, no_chdir => 1 }, $rootdir);
    
	foreach $file (@filelist) {
		### Remove $basepath/src/root-...
		$file =~ s/^$basepath\/src\/root-.+$basepath/$basepath/g;
		### Don't add DEBIAN dir
		next if ($file =~ /DEBIAN/);
	  
		($dev, $ino, $mode, $nlink, $uid, $gid) = lstat($file);
	  
		$usr = User::pwent::getpwuid($uid);
		$grp = User::grent::getgrgid($gid);
	  
		push(@files, $file);
		push(@users, $usr);
		push(@groups, $grp);
	}

	$file = join(":", @files);
	$usr = join (":", @users);
	$grp = join (":", @groups);

	$self->set_perms($rootdir, $file);

	$script = $self->build_chown_script($file, $usr, $grp);

	return $script;
}

### add check/add user script and then set perms
sub add_user_script {
	my $self = shift;
	my $name = shift;
	my $type = shift;
	my $desc = shift;
	my $pass = shift || "";
	my $shell = shift || "/usr/bin/false";
	my $home = shift || "/tmp";
	my $group = shift || $name;
    
	my $script = "";

	### FIXME
    
	return $script;
}

### Check remove user/group
sub remove_user_script {
	my $self = shift;
	my $name = shift;
	my $type = shift;
	my $script = "";
    
	### FIXME
    
	return $script
}

### build script to set user/groups
sub build_chown_script {
	my $self = shift;
	my $files = shift;
	my $users = shift;
	my $groups = shift;
	my $script = "";
	my $i = 0;
	
	### Build perms script
	my @files = split(/:/, $files);
	my @users = split(/:/, $users);
	my @groups = split(/:/, $groups);

	foreach $file (@files) {
		$script .= "chown @users[$i]:@groups[$i] $file\n";
		$i++;
	}
    
	return $script;
}

### Set everything to root:wheel before packaging to keep all debs the same
sub set_perms {
	my $self = shift;
	my $rootdir = shift;
	my $files = shift;
	
	my @files = split(/:/, $files);
	
	foreach $file (@files);
		if (&execute("chown root:wheel $file")) {
			die "Couldn't change ownershil of $file!\n";
		}
	}

	return 0;
}

### EOF
1;
