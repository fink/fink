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

use Fink::Services qw(&prompt_selection
                      &read_properties &read_properties_multival
                      &execute &filename);
use Fink::Config qw($config $basepath $libpath);

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
  return &fetch_url_to_file($url, $file, {}, 0, $destdir);
}

### download a file to the designated directory and save it under the
### given name
# returns 0 on success, 1 on error

sub fetch_url_to_file {
  my $origurl = shift;
  my $file = shift;
  my $custom_mirrors = shift || {};
  my $tries = shift || 0;
  my $destdir = shift || "$basepath/src";
  my ($http_proxy, $ftp_proxy);
  my ($url, $cmd, $failed, $result);

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

  if ($origurl =~ /^mirror\:(\w+)\:(.*)$/) {
    my $mirror = $1;
    my $path = $2;
    my $mirror_level = 0;
    my ($all_mirrors);
    
    # read the mirror list
    if ($mirror eq "custom") {
      $all_mirrors = $custom_mirrors;
    } else {
      $all_mirrors = &read_properties_multival("$libpath/mirror/$mirror");
    }

    $url = "";

    do {
  
      ### resolve mirror url
  
      if ($mirror_level <= 0 && $mirror ne "custom") {
	# use last / preconfigured mirror
	if (!$url) {
	  if ($Fink::Config::config->has_param("mirror-$mirror")) {
	    $url = $Fink::Config::config->param("mirror-$mirror");
	    $url .= "/" unless $url =~ /\/$/;
	    $url .= $path;
	  } else {
	    # FIXME: pick a mirror at random
	    die "can't find url for mirror $mirror in configuration";
	  }
	}
      } else {
	# pick a mirror at random, $mirror_level controls the scope
	my ($key, $site, $match, @list);
	
	if ($mirror_level == 1) {
	  $match = lc $config->param_default("MirrorCountry", "nam-us");
	} elsif ($mirror_level == 2) {
	  $match = lc $config->param_default("MirrorContinent", "nam");
	} else {
	  $match = "";
	}

	@list = ();
	foreach $key (keys %$all_mirrors) {
	  if ($key =~ /^$match/) {
	    foreach $site (@{$all_mirrors->{$key}}) {
	      push @list, $site;
	    }
	  }
	}
	if ($#list < 0 && exists $all_mirrors->{primary}) {
	  foreach $site (@{$all_mirrors->{primary}}) {
	    push @list, $site;
	  }
	}
	if ($#list < 0) {
	  die "No mirrors found for mirror list \"$mirror\", not even a primary site. Check the mirror lists.";
	}

	$url = $list[int(rand(scalar(@list)))];
	$url .= "/" unless $url =~ /\/$/;
	$url .= $path;
      }
  
      ### fetch $url to $file
  
      if (-f $file) {
	&execute("rm -f $file");
      }
      if (&execute("$cmd $url") or not -f $file) {
	$failed = 1;
      } else {
	$failed = 0;
      }
  
      ### failure handling
  
      if ($failed) {
	$result =
	  &prompt_selection("Downloading the file \"$file\" failed. ".
			    "How do you want to proceed?",
			    ($tries > 5) ? 1 : (($tries > 3) ? 5 : 4),
			    { "error" => "Give up",
			      "retry" => "Retry the same mirror",
			      "retry-country" => "Retry a random mirror from your country",
			      "retry-continent" => "Retry a random mirror from your continent",
			      "retry-world" => "Retry a random mirror" },
			    "error", "retry", "retry-country", "retry-continent", "retry-world");
	if ($result eq "error") {
	  return 1;
	} elsif ($result eq "retry") {
	  $mirror_level = 0;
	} elsif ($result eq "retry-country") {
	  $mirror_level = 1;
	} elsif ($result eq "retry-continent") {
	  $mirror_level = 2;
	} elsif ($result eq "retry-world") {
	  $mirror_level = 3;
	}
	$tries++;
      }
  
    } while ($failed);

  } else {
    $url = $origurl;

    do {

      ### fetch $url to $file
  
      if (-f $file) {
	&execute("rm -f $file");
      }
      if (&execute("$cmd $url") or not -f $file) {
	$failed = 1;
      } else {
	$failed = 0;
      }
  
      ### failure handling
  
      if ($failed) {
	$result =
	  &prompt_selection("Downloading the file \"$file\" failed. ".
			    "How do you want to proceed?",
			    ($tries > 5) ? 1 : 2,
			    { "error" => "Give up",
			      "retry" => "Retry" },
			    "error", "retry");
	if ($result eq "error") {
	  return 1;
	}
	$tries++;
      }
  
    } while ($failed);
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
    if (!$config->param_boolean("Verbose")) {
      $cmd .= " -s -S";
    }
    if (!$config->param_boolean("ProxyPassiveFTP")) {
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
    if ($config->param_boolean("Verbose")) {
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
