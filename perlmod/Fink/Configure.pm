#
# Fink::Configure module
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

package Fink::Configure;

use Fink::Config qw($config $basepath $libpath);
use Fink::Services qw(&prompt &prompt_boolean &prompt_selection
                      &print_breaking &read_properties
                      &read_properties_multival &filename);

use strict;
use warnings;

BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  $VERSION = 1.00;
  @ISA         = qw(Exporter);
  @EXPORT      = qw();
  @EXPORT_OK   = qw(&configure);
  %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }       # module clean-up code here (global destructor)


### create/change configuration interactively

sub configure {
  my ($otherdir, $verbose);
  my ($http_proxy, $ftp_proxy, $passive_ftp, $same_for_ftp, $default);

  print "\n";
  &print_breaking("OK, I'll ask you some questions and update the ".
		  "configuration file in '".$config->get_path()."'.");
  print "\n";

  # normal configuration
  $otherdir =
    &prompt("In what additional directory should Fink look for downloaded ".
	    "tarballs?",
	    $config->param_default("FetchAltDir", ""));
  if ($otherdir) {
    $config->set_param("FetchAltDir", $otherdir);
  }

  $verbose =
    &prompt_boolean("Always print verbose messages?",
		    $config->param_boolean("Verbose"));
  $config->set_param("Verbose", $verbose ? "true" : "false");


  # proxy settings
  print "\n";
  &print_breaking("Proxy/Firewall settings");

  $default = $config->param_default("ProxyHTTP", "");
  $default = "none" unless $default;
  $http_proxy =
    &prompt("Enter the URL of the HTTP proxy to use, or 'none' for no proxy. ".
	    "The URL should start with http:// and may contain username, ".
	    "password or port specifications.",
	    $default);
  if ($http_proxy =~ /^none$/i) {
    $http_proxy = "";
  }
  $config->set_param("ProxyHTTP", $http_proxy);

  if ($http_proxy) {
    $same_for_ftp =
      &prompt_boolean("Use the same proxy for FTP?", 0);
  } else {
    $same_for_ftp = 0;
  }

  if ($same_for_ftp) {
    $ftp_proxy = $http_proxy;
  } else {
    $default = $config->param_default("ProxyFTP", "");
    $default = "none" unless $default;
    $ftp_proxy =
      &prompt("Enter the URL of the proxy to use for FTP, ".
	      "or 'none' for no proxy. ".
	      "The URL should start with http:// and may contain username, ".
	      "password or port specifications.",
	      $default);
    if ($ftp_proxy =~ /^none$/i) {
      $ftp_proxy = "";
    }
  }
  $config->set_param("ProxyFTP", $ftp_proxy);

  $passive_ftp =
    &prompt_boolean("Use passive mode FTP transfers (to get through a ".
		    "firewall)?",
		    $config->param_boolean("ProxyPassiveFTP"));
  $config->set_param("ProxyPassiveFTP", $passive_ftp ? "true" : "false");


  # mirror selection
  &choose_mirrors();


  # write configuration
  print "\n";
  &print_breaking("Writing updated configuration to '".$config->get_path().
		  "'...");
  $config->save();
}

### mirror selection

sub choose_mirrors {
  my ($answer, $missing, $default, $def_value);
  my ($continent, $country);
  my ($keyinfo, @continents, @countries, $key, $listinfo);
  my ($mirrorfile, $mirrorname, $mirrortitle);
  my ($all_mirrors, @mirrors, $mirror_labels, $site);

  print "\n";
  &print_breaking("Mirror selection");
  $keyinfo = &read_properties("$libpath/mirror/_keys");
  $listinfo = &read_properties("$libpath/mirror/_list");

  ### step 0: determine and ask if we need to change anything

  $missing = 0;
  foreach $mirrorname (split(/\s+/, $listinfo->{order})) {
    next if $mirrorname =~ /^\s*$/;

    if (!$config->has_param("Mirror-$mirrorname")) {
      $missing = 1;
    }
  }
  if (!$missing) {
    $answer =
      &prompt_boolean("All mirrors are set. Do you want to change them?", 0);
    if (!$answer) {
      return;
    }
  }

  ### step 1: choose a continent

  $def_value = $config->param_default("MirrorContinent", "-");
  $default = 1;
  @continents = ();
  foreach $key (sort keys %$keyinfo) {
    if (length($key) == 3) {
      push @continents, $key;
      if ($key eq $def_value) {
	$default = scalar(@continents);
      }
    }
  }

  &print_breaking("Choose a continent:");
  $continent = &prompt_selection("Your continent?", $default, $keyinfo,
				 @continents);
  $config->set_param("MirrorContinent", $continent);

  ### step 2: choose a country

  $def_value = $config->param_default("MirrorCountry", "-");
  $default = 1;
  @countries = ( "-" );
  $keyinfo->{"-"} = "No selection - display all mirrors on the continent";
  foreach $key (sort keys %$keyinfo) {
    if ($key =~ /^$continent-/) {
      push @countries, $key;
      if ($key eq $def_value) {
	$default = scalar(@countries);
      }
    }
  }

  print "\n";
  &print_breaking("Choose a country:");
  $country = &prompt_selection("Your country?", $default, $keyinfo,
			       @countries);
  if ($country eq "-") {
    $country = $continent;
  }
  $config->set_param("MirrorCountry", $country);

  ### step 3: mirrors

  foreach $mirrorname (split(/\s+/, $listinfo->{order})) {
    next if $mirrorname =~ /^\s*$/;

    $mirrorfile = "$libpath/mirror/$mirrorname";
    $mirrortitle = $mirrorname;
    if (exists $listinfo->{lc $mirrorname}) {
      $mirrortitle = $listinfo->{lc $mirrorname};
    }

    $all_mirrors = &read_properties_multival($mirrorfile);

    @mirrors = ();
    $mirror_labels = {};

    $def_value = $config->param_default("Mirror-$mirrorname", "");
    if ($def_value) {
      push @mirrors, "current";
      $mirror_labels->{current} = "Current setting: $def_value";
    }
    $default = 1;

    if (exists $all_mirrors->{primary}) {
      foreach $site (@{$all_mirrors->{primary}}) {
	push @mirrors, $site;
	$mirror_labels->{$site} = "Primary: $site";
      }
    }
    if ($country ne $continent and exists $all_mirrors->{$country}) {
      foreach $site (@{$all_mirrors->{$country}}) {
	push @mirrors, $site;
	$mirror_labels->{$site} = $keyinfo->{$country}.": $site";
      }
    }
    if (exists $all_mirrors->{$continent}) {
      foreach $site (@{$all_mirrors->{$continent}}) {
	push @mirrors, $site;
	$mirror_labels->{$site} = $keyinfo->{$continent}.": $site";
      }
    }

    print "\n";
    &print_breaking("Choose a mirror for '$mirrortitle':");
    $answer = &prompt_selection("Mirror for $mirrortitle?", $default,
				$mirror_labels, @mirrors);
    if ($answer eq "current") {
      $answer = $def_value;
    }
    $config->set_param("Mirror-$mirrorname", $answer);
  }
}


### EOF
1;
