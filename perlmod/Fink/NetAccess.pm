# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::NetAccess module
#
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

package Fink::NetAccess;

use Fink::Services qw(&execute &filename &file_MD5_checksum);
use Fink::CLI qw(&prompt_selection_new &print_breaking);
use Fink::Config qw($config $basepath $libpath);
use Fink::Mirror;
use Fink::Command qw(mkdir_p rm_f);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	%EXPORT_TAGS = ( );			# eg: TAG => [ qw!name1 name2! ],

	# your exported package globals go here,
	# as well as any optionally exported functions
	@EXPORT_OK	 = qw(&fetch_url &fetch_url_to_file);
}
our @EXPORT_OK;

END { }				# module clean-up code here (global destructor)


### download a file to the designated directory
# returns 0 on success, 1 on error
# Does not allow master mirroring

sub fetch_url {
	my $url = shift;
	my $downloaddir = shift || "$basepath/src";
	my ($file, $cmd);

	$file = &filename($url);
	return &fetch_url_to_file($url, $file, 0, 0, 0, 1, 0, $downloaddir, undef);
}

### download a file to the designated directory and save it under the
### given name
# Allows custom & master mirroring
# returns 0 on success, 1 on error

sub fetch_url_to_file {
	my $origurl = shift;
	my $file = shift;
	my $custom_mirror = shift || 0;
	my $tries = shift || 0;
	my $cont = shift || 0;	
	my $nomirror = shift || 0;
	my $dryrun = shift || 0;
	my $downloaddir = shift || "$basepath/src";
	my $checksum = shift;
	my ($http_proxy, $ftp_proxy);
	my ($url, $cmd, $cont_cmd, $result);
	my $found_archive_sum;

	# create destination directory if necessary
	if (not -d $downloaddir) {
		mkdir_p $downloaddir or
			die "Download directory \"$downloaddir\" can not be created!\n";
	}
	chdir $downloaddir;

	# determine download command
	$cmd = &download_cmd($origurl, $file);
	$cont_cmd = &download_cmd($origurl, $file, 1);

	# set proxy env vars
	$http_proxy = $config->param_default("ProxyHTTP", "");
	if ($http_proxy) {
		$ENV{http_proxy} = $http_proxy;
		$ENV{HTTP_PROXY} = $http_proxy;
	}
	$ftp_proxy = $config->param_default("ProxyFTP", "");
	if ($ftp_proxy) {
		$ENV{ftp_proxy} = $ftp_proxy;
		$ENV{FTP_PROXY} = $ftp_proxy;
	}
	
	my ($mirrorname, $origmirror, $nextmirror);
	my ($mirrorindex, $mirrororder, @mirror_list);
	my ($path, $basename, $masterpath);

	$mirrorindex = 0;
	if ($origurl =~ m#^mirror\:(\w+)\:(.*?)([^/]+$)#g) {
		$mirrorname = $1;
		$path = $2;
		$basename = $3;
		$path =~ s/^\/*//;    # Mirror::get_site always returns a / at the end
		if ($mirrorname eq "custom") {
			if (not $custom_mirror) {
				die "Source file \"$file\" uses mirror:custom, but the ".
					"package doesn't specify a mirror site list.\n";
			}
			$origmirror = $custom_mirror;
		} else {
			$origmirror = Fink::Mirror->get_by_name($mirrorname);
		}		
		if($dryrun) {
		  $origmirror->initialize(); # We want every mirror when printing
		}
	} elsif ($origurl =~  m|^file://   			
							(.*?)						# (optional) Path into $1
							([^/]+$)   					# Tarball into $2
					 	 |x  ) { 
		# file:// URLs
		$path = "file://$1";
		$basename = $2;
		$nomirror = 1;
		#wget does not support file::. Use curl for this fetch. All 10.2+ & 6+ have it.
		if($config->param_default("DownloadMethod") eq "wget")
		{	
			&print_breaking("Notice: wget does not support file://. Using curl for this fetch.");
			$config->set_param("DownloadMethod", "curl");
			$cmd = &download_cmd($origurl, $file);
			$cont_cmd = &download_cmd($origurl, $file, 1);
			$config->set_param("DownloadMethod", "wget")
		}
	} elsif ($origurl =~  m|^([^:]+://[^/]+/)			# Match http://domain/ into $1
							(.*?)						# (optional) Path into $2
							([^/]+$)   					# Tarball into $3
					 	 |x  ) { 
		# Not a custom mirror, parse a full URL
		$path = $2;
		$basename = $3;
		$origmirror = Fink::Mirror->new_from_url($1);
	} else {
		# $origurl did not match. Probably a bare tarball name. Check for it
		# If its not there, fail. No need to ask, since 
		# We don't complain if they already exists, because the bootstrap does this.
		if (-f $file)
		{
			return 0;
		} else {
			return 1;			
		}
	}

	# set up the mirror ordering
	$mirrororder = $config->param_default("MirrorOrder", "MasterLast");
	if($mirrororder eq "MasterNever" || $dryrun) {
	  $nomirror = 1;
	}
	if($nomirror == 0) {
		push(@mirror_list, Fink::Mirror->get_by_name("master"));
		$masterpath = ""; # Add package sections, etc here perhaps?
		if($mirrororder eq "MasterFirst") {
			push(@mirror_list, $origmirror);
		} elsif($mirrororder eq "MasterLast") {
			unshift(@mirror_list, $origmirror);
		} elsif($mirrororder eq "ClosestFirst") {
			$origmirror->merge_master_mirror($mirror_list[0]);
			$mirror_list[0] = $origmirror;
		}
	} else {
	  if(defined $origmirror) {
		  push(@mirror_list, $origmirror);
		}
	}
	if(defined $mirror_list[0]) {
	  $url = $mirror_list[0]->get_site();
	}

	### if the file already exists, ask user what to do
	if (-f $file && !$cont && !$dryrun) {
		my $checksum_msg = ". ";
		my $default_value = "retry"; # Play it save, assume redownload as default
		$found_archive_sum = &file_MD5_checksum($file);
		if (defined $checksum) {
			if ($checksum eq $found_archive_sum) {
				$checksum_msg = " and its checksum matches. ";
				$default_value = "use_it"; # MD5 matches: assume okay to use it
			} else {
				$checksum_msg = " but its checksum does not match. The most likely ".
								"cause for this is a corrupted or incomplete download\n".
								"Expected: $checksum \nActual: $found_archive_sum \n";
			}
		}
		$result = &prompt_selection_new("The file \"$file\" already exists".$checksum_msg."How do you want to proceed?",
						[ value => $default_value ],
						( "Delete it and download again" => "retry",
						  "Assume it is a partial download and try to continue" => "continue",
						  "Don't download, use existing file" => "use_it" ) );
		if ($result eq "retry") {
			rm_f $file;
		} elsif ($result eq "continue") {
			$cont = 1;
		} elsif ($result eq "use_it") {
			# pretend success, return to caller
			return 0;
		}
	}

	while (1) {	 # retry loop, left with return in case of success
		
		if($mirrorindex < $#mirror_list) { 
		 	$nextmirror = $mirror_list[$mirrorindex + 1]->{name};
		} else {
			$nextmirror = "";
		}
		
		if(defined $url && 
		   (($url =~ /^master:/) || ($mirror_list[$mirrorindex]->{name} eq "master"))) {
			$url =~ s/^master://;
			$url .= $masterpath . $file;    # SourceRenamed tarball name
		} else {
			$url .= $path . $basename;
		}

		### fetch $url to $file

		if (!$dryrun && -f $file) {
			if (not $cont) {
				rm_f $file;
			}
		} else {
			$cont = 0;
		}
		
		if ($dryrun) {
			print " $url";
		} elsif ($cont) {
			$result = &execute("$cont_cmd $url");
			$cont = 0;
		} else {
			$result = &execute("$cmd $url");
		}
		
		if ($dryrun or ($result or not -f $file)) {
			# failure, continue loop
		} else {
			$found_archive_sum = &file_MD5_checksum($file);
			if (defined $checksum and $checksum ne $found_archive_sum) {

				&print_breaking("The checksum of the file is incorrect. The most likely ".
								"cause for this is a corrupted or incomplete download\n".
								"Expected: $checksum \nActual: $found_archive_sum \n");
				# checksum failure, continue loop
			} else {
				# success, return to caller
				return 0;
			}
		}

		### failure handling
		if(not $dryrun) {
			&print_breaking("Downloading the file \"$file\" failed.");
			$tries++;
		}

		# let the Mirror object handle this mess...
		RETRY: {
			if(defined $mirror_list[$mirrorindex])
			{
				$url = $mirror_list[$mirrorindex]->get_site_retry($nextmirror, $dryrun);
			} else {
				return 1;	
			}
		}
		if ($url eq "retry-next") {
			# Start new mirror with the last used site, or first site
			$url = $mirror_list[$mirrorindex + 1]->get_site();
			$mirrorindex++;
			if($mirrorindex < $#mirror_list) { 
				$nextmirror = $mirror_list[$mirrorindex + 1]->{name};
			} else {
				$nextmirror = "";
			}
		} elsif (not $url) {
		# user chose to give up/out of mirrors
			return 1;
		}
  	}
  	return 0;
}

sub download_cmd {
	my $url = shift;
	# $file is the post-SourceRename tarball name
	my $file = shift || &filename($url);
	my $cont = shift || 0;	# Continue a previously started download?
	my $cmd;

	# determine the download command
	$cmd = "";

	# check if we have curl
	if (-x "$basepath/bin/curl" or -x "/usr/bin/curl") {
		$cmd = "curl -f -L";
		if (Fink::Config::verbosity_level() == 0) {
			$cmd .= " -s -S";
		}
		if (not $config->param_boolean("ProxyPassiveFTP")) {
			$cmd .= " -P -";
		}
		if ($file ne &filename($url)) {
			$cmd .= " -o $file";
		} else {
			$cmd .= " -O"
		}
		if ($cont) {
			$cmd .= " -C -"
		}
	}

	# if we would prefer wget (or didn't have curl available), check for wget
	if ((!$cmd or $config->param_default("DownloadMethod") eq "wget") and
			(-x "$basepath/bin/wget" or -x "/usr/bin/wget")) {
		$cmd = "wget";
		if (Fink::Config::verbosity_level() >= 1) {
			$cmd .= " --verbose";
		} else {
			$cmd .= " --non-verbose";
		}
		if ($config->param_boolean("ProxyPassiveFTP")) {
			$cmd .= " --passive-ftp";
		}
		if ($file ne &filename($url)) {
			$cmd .= " -O $file";
		}
		if ($cont) {
			$cmd .= " -c"
		}
	}

	# if we would prefer axel (or didn't have curl or wget available), check for axel
	if ((!$cmd or $config->param_default("DownloadMethod") eq "axel"
						 or $config->param_default("DownloadMethod") eq "axelautomirror") and
			(-x "$basepath/bin/axel" or -x "/usr/bin/axel")) {
		$cmd = "axel";
		if ($config->param_default("DownloadMethod") eq "axelautomirror") {
			$cmd = "axel -S 1";
		}
		if (Fink::Config::verbosity_level() >= 1) {
			$cmd .= " --verbose";
		}
		if ($file ne &filename($url)) {
			$cmd .= " -o $file";
		}
		# Axel always continues downloads, by default
	}
	
	if (!$cmd) {
		die "Can't locate a download program. Install either curl, wget, or axel.\n";
	}

	return $cmd;
}


### EOF
1;
