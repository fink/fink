#
# Fink::NetAccess module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

package Fink::NetAccess;

use Fink::Services qw(&prompt_selection &print_breaking
                      &execute &filename);
use Fink::Config qw($config $basepath $libpath);
use Fink::Mirror;

use strict;
use warnings;

BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  $VERSION = 1.00;
  @ISA         = qw(Exporter);
  @EXPORT      = qw();
  %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],

  # your exported package globals go here,
  # as well as any optionally exported functions
  @EXPORT_OK   = qw(&fetch_url &fetch_url_to_file);
}
our @EXPORT_OK;

END { }       # module clean-up code here (global destructor)


### download a file to the designated directory
# returns 0 on success, 1 on error

sub fetch_url {
  my $url = shift;
  my $destdir = shift || "$basepath/src";
  my ($file, $cmd);

  $file = &filename($url);
  return &fetch_url_to_file($url, $file, 0, 0, $destdir);
}

### download a file to the designated directory and save it under the
### given name
# returns 0 on success, 1 on error

sub fetch_url_to_file {
  my $origurl = shift;
  my $file = shift;
  my $custom_mirror = shift || 0;
  my $tries = shift || 0;
  my $destdir = shift || "$basepath/src";
  my ($http_proxy, $ftp_proxy);
  my ($url, $cmd, $result);

  # create destination directory if necessary
  if (not -d $destdir) {
    &execute("mkdir -p $destdir");
    if (not -d $destdir) {
      die "Download directory \"$destdir\" can not be created!\n";
    }
  }
  chdir $destdir;

  # determine download command
  $cmd = &download_cmd($origurl, $file);

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

  my ($mirrorname, $mirror, $path);
  if ($origurl =~ /^mirror\:(\w+)\:(.*)$/) {
    $mirrorname = $1;
    $path = $2;
    if ($mirrorname eq "custom") {
      if (not $custom_mirror) {
	die "Source tarball \"$file\" uses mirror:custom, but the ".
	  "package doesn't specify a mirror site list.\n";
      }
      $mirror = $custom_mirror;
    } else {
      $mirror = Fink::Mirror->get_by_name($mirrorname);
    }

    $url = $mirror->get_site();
    $url .= $path;

  } else {
    $mirrorname = "";
    $path = $origurl;
    $mirror = 0;

    $url = $origurl;
  }

  while (1) {  # retry loop, left with return in case of success

    ### fetch $url to $file

    if (-f $file) {
      &execute("rm -f $file");
    }
    if (&execute("$cmd $url") or not -f $file) {
      # failure, continue loop
    } else {
      # success, return to caller
      return 0;
    }

    ### failure handling

    &print_breaking("Downloading the file \"$file\" failed.");

    $tries++;

    if ($mirror) {
      # let the Mirror object handle this mess...
      $url = $mirror->get_site_retry();
      if (not $url) {
	# user chose to give up
	return 1;
      }
      $url .= $path;

    } else {
      $result =
	&prompt_selection("How do you want to proceed?",
			  ($tries >= 5) ? 1 : 2,
			  { "error" => "Give up",
			    "retry" => "Retry" },
			  "error", "retry");
      if ($result eq "error") {
	return 1;
      }

    }  # using mirrors

  }

  return 0;
}

sub download_cmd {
  my $url = shift;
  my $file = shift || &filename($url);
  my $cmd;

  # determine the download command
  $cmd = "";

  # check if we have curl
  if (-x "$basepath/bin/curl" or -x "/usr/bin/curl") {
    $cmd = "curl -L";
    if (not Fink::Config::is_verbose()) {
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
  }

  # check if we have wget
  if (!$cmd and (-x "$basepath/bin/wget" or -x "/usr/bin/wget")) {
    $cmd = "wget";
    if (Fink::Config::is_verbose()) {
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
  }

  if (!$cmd) {
    die "Can't locate a download program. Install either curl or wget.\n";
  }

  return $cmd;
}


### EOF
1;
