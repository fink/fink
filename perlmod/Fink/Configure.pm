#
# Fink::Configure module
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

package Fink::Configure;

use Fink::Config qw($config $basepath $libpath);
use Fink::Services qw(&prompt &prompt_boolean &prompt_selection_new
					  &print_breaking &read_properties
					  &read_properties_multival &filename);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw(&configure &choose_mirrors);
	%EXPORT_TAGS = ( );			# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }				# module clean-up code here (global destructor)


### create/change configuration interactively

sub configure {
	my ($otherdir, $builddir, $verbose);
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

	$builddir =
		&prompt("Which directory should Fink use to build packages? \(If you don't ".
				"know what this means, it is safe to leave it at its default.\)",
				$config->param_default("Buildpath", ""));
	if ($builddir) {
		$config->set_param("Buildpath", $builddir);
	}

	$verbose = $config->param_default("Verbose", 1);
	$verbose =
		&prompt_selection_new("How verbose should Fink be?",
				      [value=>$verbose], 
				      ( "Quiet (don't show download stats)" => 0,
					"Low (don't show tarballs being expanded)" => 1,
					"Medium (shows almost everything)" => 2,
					"High (shows everything)" => 3 ) );
	$config->set_param("Verbose", $verbose);

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

	$passive_ftp = $config->param_boolean("ProxyPassiveFTP");
	# passive FTP is the safe default
	if (!$config->has_param("ProxyPassiveFTP")) {
		$passive_ftp = 1;
	}
	$passive_ftp =
		&prompt_boolean("Use passive mode FTP transfers (to get through a ".
						"firewall)?", $passive_ftp);
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
	my $mirrors_postinstall = shift; # boolean value, =1 if we've been
					# called from the postinstall script
 					# of the fink-mirrors package
	my ($answer, $missing, $default, $def_value);
	my ($continent, $country);
	my ($keyinfo, $listinfo);
	my ($mirrorfile, $mirrorname, $mirrortitle);
	my ($all_mirrors, @mirrors, $site, $mirror_order);

	print "\n";
	&print_breaking("Mirror selection");
	die "File $libpath/mirror/_keys not found.  Please install the fink-mirrors package and try again.\n" unless (-f "$libpath/mirror/_keys");
	$keyinfo = &read_properties("$libpath/mirror/_keys");
	die "File $libpath/mirror/_list not found.  Please install the fink-mirrors package and try again.\n" unless (-f "$libpath/mirror/_list");
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
		if ($mirrors_postinstall) {
			print "\n";
			$answer = &prompt_boolean("The list of possible mirrors in fink has" .
				" been updated.  Do you want to review and change your choices?", 0);
	} else {
		$answer =
			&prompt_boolean("All mirrors are set. Do you want to change them?", 0);
	}
		if (!$answer) {
			return;
		}
	}
	
	&print_breaking("\nThe Fink team maintains mirrors known as \"Master\" mirrors, which contain ".
    				  "the sources for all fink packages. You can choose to use these mirrors first, ".
					  "last, never, or mixed in with regular mirrors. If you don't care, just select the default.\n");
	
	$mirror_order = &prompt_selection_new("What mirror order should fink use when downloading sources?",
					      [number=>1], 
					      ( "Search \"Master\" source mirrors first." => "MasterFirst",
						"Search \"Master\" source mirrors last." => "MasterLast",
						"Never use \"Master\" source mirrors." => "MasterNever",
						"Search closest source mirrors first. (combine all mirrors into one set)" => "ClosestFirst" ) );
	$config->set_param("MirrorOrder", $mirror_order);
	
	### step 1: choose a continent
	&print_breaking("Choose a continent:");
	$continent = &prompt_selection_new("Your continent?",
					   [ value => $config->param_default("MirrorContinent", "-") ],
					   map { length($_)==3 ? ($keyinfo->{$_},$_) : () } sort keys %$keyinfo);
	$config->set_param("MirrorContinent", $continent);

	### step 2: choose a country
	print "\n";
	&print_breaking("Choose a country:");
	$country = &prompt_selection_new("Your country?",
					 [ value => $config->param_default("MirrorCountry", $continent) ],
					 ( "No selection - display all mirrors on the continent" => $continent,
					   map { /^$continent-/ ? ($keyinfo->{$_},$_) : () } sort keys %$keyinfo ) );
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

		$def_value = $config->param_default("Mirror-$mirrorname", "");
		if ($def_value) {
			push @mirrors, ( "Current setting: $def_value" => $def_value );
		}

		if (exists $all_mirrors->{primary}) {
			push @mirrors, map { ( "Primary: $_" => $_ ) } @{$all_mirrors->{primary}};
		}
		if ($country ne $continent and exists $all_mirrors->{$country}) {
			push @mirrors, map { ( $keyinfo->{$country}.": $_" => $_ ) } @{$all_mirrors->{$country}};
		}
		if (exists $all_mirrors->{$continent}) {
			push @mirrors, map { ( $keyinfo->{$continent}.": $_" => $_ ) } @{$all_mirrors->{$continent}};
		}

		print "\n";
		&print_breaking("Choose a mirror for '$mirrortitle':");
		$answer = &prompt_selection_new("Mirror for $mirrortitle?",
						[ number => 1 ],
						@mirrors );
		$config->set_param("Mirror-$mirrorname", $answer);
	}
}


### EOF
1;
