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

$lowUID = $config->param("lowUID") || 250;
$highUID = $config->param("highUID") || 299;
$lowGID = $config->param("lowGID") || 250;
$highGID = $config->param("highGID") || 299;

END { }				# module clean-up code here (global destructor)

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

	my pass = "*";
	my $script = "";

	### FIXME need to figure a way ehre to get and set uids and gids, and
	### ask if the fink.conf specifies this.  maybe use a grep on fink.conf

	if ($type eq "user") {
		$script =
			"getgid() {\n".
			"gid=`$nidump group . | $grep -e \"^$name:\" | $cut -d\":\" -f3`\n".
			"if [ ! \$gid ]; then\n".
			"\n".
			"fi\n".
			"}\n".
			"getuid() {\n".
			"uid=`$nidump passwd . | $grep -e \"^$name:\" | $cut -d\":\" -f3`\n".
			"if [ ! \$uid ]; then\n".
			"\n".
			"fi\n".
			"}\n".
			"uid=getuid()\n".
			"gid=getgid()\n".
			"$niutil -create . /users/$name\n".
			"$niutil -createprop . /users/$name realname \"$desc\"\n".
			"$niutil -createprop . /users/$name gid \$gid\n".
			"$niutil -createprop . /users/$name uid \$uid\n".
			"$niutil -createprop . /users/$name home \"$home\"\n".
			"$niutil -createprop . /users/$name name \"$user\"\n".
			"$niutil -createprop . /users/$name passwd \"$pass\"\n".
			"$niutil -createprop . /users/$name shell \"$shell\"\n".
			"$niutil -createprop . /users/$name change 0\n".
			"$niutil -createprop . /users/$name expire 0\n".
			"$mkdir \"$home\"\n".
			"$chown \"$name.$group\" \"$home\"\n".
			"\n";
	} else {
		$script =
			"getgid() {\n".
			"gid=`$nidump group . | $grep -e \"^$name:\" | $cut -d\":\" -f3`\n".
			"if [ ! \$gid ]; then\n".
			"\n".
			"fi\n".
			"}\n".
			"\n";
			"gid=getgid()\n".
                	"$niutil -create . /groups/$user\n".
        		"$niutil -createprop . /groups/$name name \"$name\"\n".
                	"$niutil -createprop . /groups/$user gid \$gid\n".
			"$niutil -createprop . /groups/$user passwd \"$pass\"\n".
			"\n";
	}
    
	return $script;
}

### Check remove user/group
sub remove_user {
	my $self = shift;
	my $name = shift;
	my $type = shift;

	my $nidump = "/usr/bin/nidump";
	my $grep = "/usr/bin/grep";
	my $cut = "/usr/bin/cut";
	my $rm = "/bin/rm -rf";

	my $script = "";
    
	if ($type eq "user") {
		$script =
			"HomeDir=`$nidump passwd . | $grep '$name:' ".
				"| $cut -d\":\" -f9`\n".
			"$rm \$HomeDir\n".
			"$niutil -destroy . /users/$name\n".
			"\n";
	} else {
		$script =
			"$niutil -destroy . /groups/$name\n".
			"\n";
	}
    
	return $script
}

### build script to set user/groups
sub get_chown {
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
		$script .= "/usr/sbin/chown \"@users[$i].@groups[$i]\" \"$file\"\n";
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
		if (&execute("/usr/sbin/chown \"0.0\" \"$file"\")) {
			die "Couldn't change ownershil of $file!\n";
		}
	}

	return 0;
}

### EOF
1;
