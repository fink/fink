# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::NetAccess module
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

package Fink::NetAccess;

use Fink::Services qw(&execute &filename);
use Fink::CLI qw(&prompt_selection &print_breaking);
use Fink::Config qw($config $basepath $libpath);
use Fink::Mirror;
use Fink::Command qw(mkdir_p rm_f);
use Fink::FinkVersion qw(&fink_version);


use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.10;
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
	return &fetch_url_to_file($url, $file, 0, 0, 0, 1, 0, $downloaddir, undef, undef);
}

### download a file to the designated directory and save it under the
### given name
# Allows custom & master mirroring
# returns 0 on success, 1 on error

sub fetch_url_to_file {
	my ($origurl, $file, $custom_mirror, $tries, $cont, $nomirror, $dryrun, $downloaddir, $checksum, $checksum_type) = @_;
	my $options = {};

	if (ref $origurl eq 'HASH')
	{
		  $options = $origurl;

		  $origurl       = $options->{'url'};
		  $file          = $options->{'filename'};
		  $custom_mirror = $options->{'custom_mirror'};
		  $tries         = $options->{'tries'};
		  $cont          = $options->{'continue'};
		  $nomirror      = $options->{'skip_master_mirror'};
		  $dryrun        = $options->{'dry_run'};
		  $downloaddir   = $options->{'download_directory'};
		  $checksum      = $options->{'checksum'};
		  $checksum_type = $options->{'checksum_type'};
	}

	$custom_mirror = $custom_mirror || 0;
	$tries         = $tries         || 0;
	$cont          = $cont          || 0;
	$nomirror      = $nomirror      || 0;
	$dryrun        = $dryrun        || 0;
	$downloaddir   = $downloaddir   || "$basepath/src";

	my ($http_proxy, $ftp_proxy);
	my ($url, $cmd, $cont_cmd, $result, $cmd_url);

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
	my ($path, $basename);

	$mirrorindex = 0;
	if ($origurl =~ m/^mirror\:(\w+)\:(.*?)([^\/]+\Z)/g) {
		$mirrorname = $1;
		$path = $2;
		$basename = $3;
		$path =~ s/^\/*//;    # Mirror::get_site always returns a / at the end
		if ($mirrorname eq "master") {
			# if the original Source spec is mirror:master, don't also consider
			# the master-mirror pool
			$nomirror = 1;
		}
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
							([^/]+\Z)  					# Tarball into $2
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
							([^/]+\Z)  					# Tarball into $3
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
		my $default_value = "retry"; # Play it safe, assume redownload as default
		if (defined $checksum and defined $checksum_type) {
			my $checksum_obj = Fink::Checksum->new($checksum_type);
			my $found_archive_sum = $checksum_obj->get_checksum($file);
			if ($checksum eq $found_archive_sum) {
				$checksum_msg = " and its checksum matches. ";
				$default_value = "use_it"; # checksum matches: assume okay to use it
			} else {
				my %archive_sums = %{Fink::Checksum->get_all_checksums($file)};
				$checksum_msg = " but its checksum does not match. The most likely ".
								"cause for this is a corrupted or incomplete download\n".
								"Expected: $checksum\nActual: " .
								join("        ", map "$_($archive_sums{$_})\n", sort keys %archive_sums);
			}
		}
		if (exists $options->{'try_all_mirrors'} and $options->{'try_all_mirrors'})
		{
			$result = $default_value;
		}
		else
		{
			$result = &prompt_selection("How do you want to proceed?",
				intro   => "The file \"$file\" already exists".$checksum_msg,
				default => [ value => $default_value ],
				choices => [
					"Delete it and download again" => "retry",
					"Assume it is a partial download and try to continue" => "continue",
					"Don't download, use existing file" => "use_it"
				],
				category => 'fetch',
				timeout  => 120,
			);
		}
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
			$url .= $file;    # SourceRenamed tarball name
		} else {
			$url .= $path . $basename;
		}

		# protect against shell metachars
		# deprotect common URI chars that are metachars for regex not shell
		( $cmd_url = "\Q$url\E" ) =~ s{\\([/.:\-=])}{$1}g;

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
			$result = &execute("$cont_cmd $cmd_url");
			$cont = 0;
		} else {
			$result = &execute("$cmd $cmd_url");
		}
		
		if ($dryrun or ($result or not -f $file)) {
			# failure, continue loop
		} else {
			if (defined $checksum and (not Fink::Checksum->validate($file, $checksum, $checksum_type))) {
				my %archive_sums = %{Fink::Checksum->get_all_checksums($file)};
				&print_breaking("The checksum of the file is incorrect. The most likely ".
								"cause for this is a corrupted or incomplete download\n".
								"Expected: $checksum\nActual: " . 
								join("        ", map "$_($archive_sums{$_})\n", sort keys %archive_sums));
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
				my $non_interactive = $dryrun;
				$non_interactive = $options->{'try_all_mirrors'} if (exists $options->{'try_all_mirrors'} and $options->{'try_all_mirrors'});
				$url = $mirror_list[$mirrorindex]->get_site_retry($nextmirror, $non_interactive);
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
	my($cmd, $cmd_file);

	# protect against shell metachars
	# deprotect common URI chars that are metachars for regex not shell
	if ($file =~ /\//) {
		die "security error: Cannot use path sep in target filename (\"$file\")\n";
	}
	( $cmd_file = "\Q$file\E" ) =~ s{\\([/.:\-=])}{$1}g;

	# determine the download command
	$cmd = "";

	# check if we have curl
	if (-x "$basepath/bin/curl" or -x "/usr/bin/curl") {
		$cmd = "curl --connect-timeout 30 -f -L -A 'fink/". Fink::FinkVersion::fink_version() ."'";
		if ($config->verbosity_level() == 0) {
			$cmd .= " -s -S";
		}
		if ($config->has_param("DownloadTimeout"))
		{
			$cmd .= " --max-time " . int($config->param("DownloadTimeout"));
		}
		if (not $config->param_boolean("ProxyPassiveFTP")) {
			$cmd .= " -P -";
		}
		if ($file ne &filename($url)) {
			$cmd .= " -o $cmd_file";
		} else {
			$cmd .= " -O"
		}
		if ($cont) {
			$cmd .= " -C -"
		}
	}

	# if we would prefer wget (or didn't have curl available), check for wget
	if (!$cmd or $config->param_default("DownloadMethod") eq "wget") {
		if (-x "$basepath/bin/wget" or -x "/usr/bin/wget") {
			$cmd = "wget -U 'fink/". Fink::FinkVersion::fink_version() ."'";
			if ($config->verbosity_level() >= 1) {
				$cmd .= " --verbose";
			} else {
				$cmd .= " -nv";
			}
			if ($config->param_boolean("ProxyPassiveFTP")) {
				$cmd .= " --passive-ftp";
			}
			#if ($file ne &filename($url)) {
			# always use -O to handle complex URLs
				$cmd .= " -O $cmd_file";
			#}
			if ($cont) {
				$cmd .= " -c"
			}
		} elsif ($config->param_default("DownloadMethod") eq "wget") {
			&print_breaking("Cannot use DownloadMethod:".$config->param_default("DownloadMethod")." (program not found)");
		}
	}

	# if we would prefer axel (or didn't have curl or wget available), check for axel
	if (!$cmd or $config->param_default("DownloadMethod") eq "axel"
						 or $config->param_default("DownloadMethod") eq "axelautomirror") {
		if (-x "$basepath/bin/axel" or -x "/usr/bin/axel") {
			$cmd = "axel";
			if ($config->param_default("DownloadMethod") eq "axelautomirror") {
				$cmd = "axel -S 1";
			}
			if ($config->verbosity_level() >= 1) {
				$cmd .= " -v";
			}
			if ($file ne &filename($url)) {
				$cmd .= " -o $cmd_file";
			}
			# Axel always continues downloads, by default
		} elsif ($config->param_default("DownloadMethod") eq "axel" or $config->param_default("DownloadMethod") eq "axelautomirror") {
			&print_breaking("Cannot use DownloadMethod:".$config->param_default("DownloadMethod")." (program not found)");
		}
	}

	# lftpget doesn't let us rename a file as we download, so we skip unless $file eq &filename($url)
	if (!$cmd or $config->param_default("DownloadMethod") eq "lftpget") {
		if (-x "$basepath/bin/lftpget" or -x "/usr/bin/lftpget") {
			if ($file eq &filename($url)) {
				$cmd = "lftpget";
				if ($config->verbosity_level() >= 1) {
					$cmd .= " -v";
				}
				if ($cont) {
					$cmd .= " -c";
				}
			} else {
				&print_breaking("Cannot use DownloadMethod:".$config->param_default("DownloadMethod")." (no support for renaming the downloaded file)");
			}
		} elsif ($config->param_default("DownloadMethod") eq "lftpget") {
			&print_breaking("Cannot use DownloadMethod:".$config->param_default("DownloadMethod")." (program not found)");
		}
	}

	# if we would prefer aria2 (or didn't have anything else available), check for aria2
	if (!$cmd or $config->param_default("DownloadMethod") eq "aria2") {
		if (-x "$basepath/bin/aria2c" or -x "/usr/bin/aria2c") {
			$cmd = "aria2c --connect-timeout 30 --allow-overwrite=true --auto-file-renaming=false -U 'fink/". Fink::FinkVersion::fink_version() ."'";
			if ($config->verbosity_level() == 0) {
				$cmd .= " -q";
			}
			if (not $config->param_boolean("ProxyPassiveFTP")) {
				$cmd .= " --ftp-pasv=false";
			}
			if ($file ne &filename($url)) {
				$cmd .= " -o $cmd_file";
			}
			if ($cont) {
				$cmd .= " -c"
			}
		}
	}

	if (!$cmd) {
		die "Can't locate a download program. Install either curl, wget, axel, or lftpget.\n";
	}

	return $cmd;
}


### EOF
1;
# vim: ts=4 sw=4 noet
