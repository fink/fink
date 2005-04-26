#!/usr/bin/perl

# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2005 The Fink Package Manager Team
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

use lib "..";
use Fink::Base;
use Fink::Services qw(&filename &execute
					  &expand_percent &latest_version
					  &collapse_space &read_properties_var
					  &pkglist2lol &lol2pkglist &cleanup_lol
					  &file_MD5_checksum &version_cmp
					  &get_arch &get_system_perl_version
					  &get_path &eval_conditional &enforce_gcc);
use Fink::CLI qw(&print_breaking &prompt_boolean &prompt_selection);
use Fink::Config qw($config $basepath $libpath $debarch $buildpath $ignore_errors);
use Fink::NetAccess qw(&fetch_url_to_file);
use Fink::Mirror;
use Fink::Package;
use Fink::Status;
use Fink::VirtPackage;
use Fink::Bootstrap qw(&get_bsbase);
use Fink::Command qw(mkdir_p rm_f rm_rf symlink_f du_sk chowname touch);
use File::Basename qw(&dirname &basename);
use Fink::Notify;
use Fink::Validation;

use POSIX qw(uname strftime);
use Hash::Util;

use strict;
use warnings;

print("Fink::Services::get_osx_vers_long:  " . Fink::Services::get_osx_vers_long() . "\n"); 
print("Fink::Services::get_osx_vers:  " . Fink::Services::get_osx_vers() . "\n");
print("Fink::Services::get_kernel_vers:  " . Fink::Services::get_kernel_vers() . "\n");
print("Fink::Services::get_darwin_equiv:  " . Fink::Services::get_darwin_equiv() . "\n");
