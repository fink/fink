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

use Fink::Services qw(&execute &filename);
use Fink::Config qw($config $basepath);

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
  @EXPORT_OK   = qw(&fetch_url);
}
our @EXPORT_OK;

END { }       # module clean-up code here (global destructor)


### download a file to the designated directory
# returns 0 on success, 1 on error

sub fetch_url {
  my $url = shift;
  my $destdir = shift || "$basepath/src";
  my ($file, $params);
  my ($http_proxy, $ftp_proxy);

  if (not -d $destdir) {
    &execute("mkdir -p $destdir");
    if (not -d $destdir) {
      die "Download directory \"$destdir\" can not be created!\n";
    }
  }
  chdir $destdir;

  $file = &filename($url);
  if (-f $file) {
    &execute("rm -f $file");
  }

  $params = "";
  if ($config->param_boolean("Verbose")) {
    $params .= " --verbose";
  } else {
    $params .= " --non-verbose";
  }
  if ($config->param_boolean("ProxyPassiveFTP")) {
    $params .= " --passive-ftp";
  }
  $http_proxy = $config->param_default("ProxyHTTP", "");
  if ($http_proxy) {
    $ENV{http_proxy} = $http_proxy;
  }
  $ftp_proxy = $config->param_default("ProxyFTP", "");
  if ($ftp_proxy) {
    $ENV{ftp_proxy} = $ftp_proxy;
  }

  if (&execute("wget $params $url") or not -f $file) {
    return 1;
  }
  return 0;
}


### EOF
1;
