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
	@EXPORT_OK	 = qw();	# eg: qw($Var1 %Hashit &func3);
	%EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

our ($usrgrps, @users, @groups, $db_outdated);
our ($lowUID, $highUID, $lowGID, $highGID);

$lowUID = $config->param("lowUID") || 250;
$highUID = $config->param("highUID") || 299;
$lowGID = $config->param("lowGID") || 250;
$highGID = $config->param("highGID") || 299;

@users = ();
@groups = ();
%usrgrps = ();
$db_outdated = 1;

END { }				# module clean-up code here (global destructor)

### %usrgrps hash/info layout
### {user} ->
###   {$usrname}{$uid}      "user id range 250...299 (next avail or ask)"
###             {$gid}      "group id (primary group, group must be made first)"
###             {$homedir}  "user home directory (mkdir if need or /dev/null)"
###             {$shell}    "user shell (default: /usr/bin/false or /dev/null)"
###             {$desc}     "user description"
###             {@packages} "array of pkgs that need this user, if 0 remove"
### {group} ->
###   {$grpname}{$gid}      "group id range 250...299 (next avail or ask)"
###             {@packages} "array of pkgs that need this group, if 0 remove"

### Create User
sub add_user {
	my $self = shift;
	my $user = shift;

	my $comment = $usrgrps{usrname}->{$user}->{desc};
	my $homedir = $usrgrps{usrname}->{$user}->{homedir};
	my $group = $usrgrps{usrname}->{$user}->{group};
	my $shell = $usrgrps{usrname}->{$user}->{shell};
	my $uid = $usrgrps{usrname}->{$user}->{uid};

	my $cmd  = "$basepath/sbin/useradd -c $comment -d $homedir -e 0";
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

	my $gid = $usrgrps{grpname}->{$group}->{gid};

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
		if ($type == "group") {
			$id = &prompt("Please enter a GID for $name ".
			              "[$lowGID...$highGID] ", $id);
		} else {
			$id = &prompt("Please enter a UID for $name ".
			              "[$lowUID...$highUID] ", $id);
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

	if ($type == "user") {
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

### Get next available id
sub get_next_avail {
	my $self = shift;
	my $type = shift;
	my ($id, $user, $uid, $group, $gid, $pass);

	if ($type == "user") {
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

### Forget users and groups and reload via debs or info of installed pkgs
sub forget_ids {
	$self = shift;

	@users = ();
	@groups = ();
	%usrgrps = ();
	db_outdated = 1;
}

### get list of users and groups, either from cache or files
sub get_all_ids {
	my $self = shift;
	my $db = "$basepath/var/db/ids.db";
	my ($group, $user);

	$self->forget_ids();

	# If we have the Storable perl module, try to use the ids index
	if (-e $db) {
		eval {
			require Storable; 

			# We assume the DB is up-to-date unless told otherwise
			$db_outdated = 0;
		
			%usrgrps = %{Storable::retrieve($db)};
			foreach $group (keys %$usrgrps{group}) {
				push($group, @groups);
			}
			foreach $user (keys %$usrgrps{user}) {
				push($user, @users);
			}
		}
	}
	
	# Regenerate the DB if it is outdated
	if ($db_outdated) {
		$self->update_id_db();
	}

}

### read the infofiles and update the database, if needed and we are root
### need list of installed pkgs, only scan installed pkgs
sub update_id_db {
	my $self = shift;
}

### EOF
1;
