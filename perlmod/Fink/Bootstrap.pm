#
# Fink::Bootstrap module
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

package Fink::Bootstrap;

use Fink::Config qw($config $basepath);
use Fink::Engine;
use Fink::Services qw(prompt prompt_boolean prompt_selection print_breaking read_properties read_properties_multival filename);
use Fink::Package;

use strict;
use warnings;

BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  $VERSION = 1.00;
  @ISA         = qw(Exporter);
  @EXPORT      = qw();
  @EXPORT_OK   = qw(&bootstrap);
  %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }       # module clean-up code here (global destructor)


### create configuration interactively

sub bootstrap {
  my ($umask, $otherdir, @elist);

  print "\n";
  &print_breaking("OK, I'll ask you some questions and update the ".
		  "configuration file in '".$config->get_path()."'.");

  # normal configuration
  $umask =
    &prompt("What umask should be used by Fink? If you don't want ".
	    "Fink to set a umask, type 'none'.", "022");
  if ($umask !~ /none/i) {
    $config->set_param("UMask", $umask);
    umask oct($umask);
  }
  $otherdir =
    &prompt("In what additional directory should Fink look for downloaded ".
	    "tarballs?", "");
  if ($otherdir) {
    $config->set_param("FetchAltDir", $otherdir);
  }


  # mirror selection
  &choose_mirrors();


  # write configuration
  print "\n";
  &print_breaking("Writing updated configuration to '".$config->get_path().
		  "'...");
  $config->save();


  # install essential packages
  # TODO: better interface to Engine
  &print_breaking("I'll now install some essential packages, ".
		  "which are required for Fink operation.");
  @elist = Fink::Package->list_essential_packages();
  Fink::Engine::cmd_install(@elist);
}

### mirror selection

sub choose_mirrors {
  my ($continent, $country, $answer);
  my ($keyinfo, @continents, @countries, $key, $listinfo);
  my ($mirrorfile, $mirrorname, $mirrortitle);
  my ($all_mirrors, @mirrors, $mirror_labels, $site);

  &print_breaking("Mirror selection");
  $keyinfo = &read_properties("$basepath/fink/mirror/_keys");

  ### step 1: choose a continent

  @continents = ();
  foreach $key (sort keys %$keyinfo) {
    if (length($key) == 3) {
      push @continents, $key;
    }
  }

  &print_breaking("Choose a continent:");
  $continent = &prompt_selection("Your continent?", 1, $keyinfo,
				 @continents);

  ### step 2: choose a country

  @countries = ( "-" );
  $keyinfo->{"-"} = "No selection - display all mirrors on the continent";
  foreach $key (sort keys %$keyinfo) {
    if ($key =~ /^$continent-/) {
      push @countries, $key;
    }
  }

  print "\n";
  &print_breaking("Choose a country:");
  $country = &prompt_selection("Your country?", 1, $keyinfo,
			       @countries);
  if ($country eq "-") {
    $country = $continent;
  }

  ### step 3: mirrors

  $listinfo = &read_properties("$basepath/fink/mirror/_list");

  foreach $mirrorname (split(/\s+/, $listinfo->{order})) {
    next if $mirrorname =~ /^\s*$/;

    $mirrorfile = "$basepath/fink/mirror/$mirrorname";
    $mirrortitle = $mirrorname;
    if (exists $listinfo->{lc $mirrorname}) {
      $mirrortitle = $listinfo->{lc $mirrorname};
    }

    $all_mirrors = &read_properties_multival($mirrorfile);

    @mirrors = ();
    $mirror_labels = {};

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
    $answer = &prompt_selection("Mirror for $mirrortitle?", 1,
				$mirror_labels, @mirrors);
    $config->set_param("Mirror-$mirrorname", $answer);
  }
}


### EOF
1;
