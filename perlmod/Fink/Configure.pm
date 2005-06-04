# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Configure module
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

package Fink::Configure;

use Fink::Config qw($config $basepath $libpath);
use Fink::Services qw(&read_properties &read_properties_multival &filename);
use Fink::CLI qw(&prompt &prompt_boolean &prompt_selection_new &prompt_selection &print_breaking);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw(&configure &choose_mirrors &spotlight_warning);
	%EXPORT_TAGS = ( );			# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }				# module clean-up code here (global destructor)


### create/change configuration interactively

sub configure {
	my ($otherdir, $builddir, $verbose);
	my ($http_proxy, $ftp_proxy, $passive_ftp, $same_for_ftp, $binary_dist, $default);

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
	&spotlight_warning();

	$binary_dist = $config->param_boolean("UseBinaryDist");
	# if we are not installed in /sw, $binary_dist must be 0:
	if (not $basepath eq '/sw') {
		$binary_dist = 0;
	} else {
		# New users should use the binary dist, but an existing user who
		# is running "fink configure" should see a default answer of "no"
		# for this question... To tell these two classes of users apart,
		# we check to see if the "Verbose" parameter has been set yet.

		if (!$config->has_param("UseBinaryDist")) {
			if ($config->has_param("Verbose")) {
				$binary_dist = 0;
			} else {
				$binary_dist = 1;
			}
		}
		$binary_dist =
			&prompt_boolean("Should Fink try to download pre-compiled packages from ".
							"the binary distribution if available?", $binary_dist);
	}
	$config->set_param("UseBinaryDist", $binary_dist ? "true" : "false");

	$verbose = $config->param_default("Verbose", 1);
	$verbose =
		&prompt_selection_new("How verbose should Fink be?",
				      [value=>$verbose], 
				      ( "Quiet (do not show download statistics)" => 0,
					"Low (do not show tarballs being expanded)" => 1,
					"Medium (will show almost everything)" => 2,
					"High (will show everything)" => 3 ) );
	$config->set_param("Verbose", $verbose);

	# proxy settings
	print "\n";
	&print_breaking("Proxy/Firewall settings");

	$default = $config->param_default("ProxyHTTP", "");
	$default = "none" unless $default;
	$http_proxy =
		&prompt("Enter the URL of the HTTP proxy to use, or 'none' for no proxy. ".
				"The URL should start with http:// and may contain username, ".
				"password or port specifications.".
				" E.g: http://username:password\@hostname:port ",
				$default);
	if ($http_proxy =~ /^none$/i) {
		$http_proxy = "";
	}
	$config->set_param("ProxyHTTP", $http_proxy);

	if ($http_proxy) {
		$same_for_ftp =
			&prompt_boolean("Use the same proxy server for FTP connections?", 0);
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
					"password or port specifications.".
					" E.g: ftp://username:password\@hostname:port ",
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

=item spotlight_warning

Warn the user if they are choosing a build path which will be indexed by
Spotlight. Returns true if changes have been made to the Fink configuration,
which will need to be saved.

=cut

sub spotlight_warning {
	my $builddir = $config->param_default("Buildpath",
										  "$basepath/src/fink.build");	
	if ( $> == 0
			&& !$config->has_flag('SpotlightWarning')
			&& $builddir !~ /\.build$/
			&& $config->param("distribution") ge "10.4") {
		
		$config->set_flag('SpotlightWarning');
		
		print "\n";
		my $response =
			prompt_boolean("Your current build directory '$builddir' will be ".
				"indexed by Spotlight, which can make packages build quite ".
				"slowly.\n\n".
				"Would you like to use '$builddir.build' as your new build ".
				"directory, so that Spotlight will not index it?",
				1);
		print "\n";	
		
		$config->set_param("Buildpath", $builddir . ".build") if $response;
		return 1;
	}
	
	return 0;
}	

=item choose_mirrors

mirror selection (returns boolean indicating if mirror selections are
unchanged: true means no changes, false means changed)

=cut

sub choose_mirrors {
	my $mirrors_postinstall = shift; # boolean value, =1 if we've been
					# called from the postinstall script
 					# of the fink-mirrors package
	my ($answer, $missing, $default, $def_value);
	my ($continent, $country);
	my ($keyinfo, $listinfo);
	my ($mirrorfile, $mirrorname, $mirrortitle);
	my ($all_mirrors, @mirrors, $site, $mirror_order);
	my %obsolete_mirrors = ();
	my ($current_value, $list_of_mirrors, $property_value);
	my ($mirror_item, $is_obsolete, $obsolete_only);
	my @mirrors_to_choose;
	my ($current_prompt, $default_response, $obsolete_question);

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
		} else {
			$current_value = $config->param("Mirror-$mirrorname");
			$is_obsolete = 1;
			$list_of_mirrors = &read_properties_multival("$libpath/mirror/$mirrorname");
			delete $list_of_mirrors->{timestamp};
		  MIRROR_GEOG_LOOP:
			foreach $property_value (values %{$list_of_mirrors}) {
				foreach $mirror_item (@{$property_value}) {
					if ($current_value eq $mirror_item) {
						$is_obsolete = 0;
						last MIRROR_GEOG_LOOP;
					}
				}
			}
			if ($is_obsolete) {
				$obsolete_mirrors{$mirrorname} = 1;
			}
		}
	}


	if (!$missing) {
		if ($mirrors_postinstall) {
			# called from dpkg postinst script of fink-mirrors pkg
			print "\n";
			$answer = &prompt_boolean("The list of possible mirrors in fink has" .
				" been updated.  Do you want to review and change your choices?",
				0, 60);
		} else {
			$answer =
				&prompt_boolean("All mirrors are set. Do you want to change them?",
								0);
		}
		if (!$answer) {
			if (%obsolete_mirrors) {
				$obsolete_question = "One or more of your mirrors is set to a value which is not on the current list of mirror choices.  Do you want to leave these as you have set them?";
				if ($mirrors_postinstall) {
					$obsolete_only = !&prompt_boolean($obsolete_question, 0, 60);
				} else {
					$obsolete_only = !&prompt_boolean($obsolete_question, 0);
				}
			}
			if (!$obsolete_only) {
				return 1;
			}
		}
	}

if ((!$obsolete_only) or (!$config->has_param("MirrorOrder"))) {	

	&print_breaking("\nThe Fink team maintains mirrors known as \"Master\" mirrors, which contain ".
    				  "the sources for all fink packages. You can choose to use these mirrors first, ".
					  "last, never, or mixed in with regular mirrors. If you don't care, just select the default.\n");
	
	$mirror_order = &prompt_selection(
		"What mirror order should fink use when downloading sources?",
		default => [ value => $config->param_default("MirrorOrder", "MasterFirst") ], 
		choices => [
			"Search \"Master\" source mirrors first." => "MasterFirst",
			"Search \"Master\" source mirrors last." => "MasterLast",
			"Never use \"Master\" source mirrors." => "MasterNever",
			"Search closest source mirrors first. (combine all mirrors into one set)"
				=> "ClosestFirst"
		]);
	$config->set_param("MirrorOrder", $mirror_order);

} else {
	$mirror_order = $config->param("MirrorOrder");
}
	
	### step 1: choose a continent

if ((!$obsolete_only) or (!$config->has_param("MirrorContinent"))) {	

	&print_breaking("Choose a continent:");
	$continent = &prompt_selection("Your continent?",
		default => [ value => $config->param_default("MirrorContinent", "-") ],
		choices => [
			map { length($_)==3 ? ($keyinfo->{$_},$_) : () }
				sort keys %$keyinfo
		]
	);
	$config->set_param("MirrorContinent", $continent);

} else {
	$continent = $config->param("MirrorContinent");
}

	### step 2: choose a country

if ((!$obsolete_only) or (!$config->has_param("MirrorCountry"))) {	

	print "\n";
	&print_breaking("Choose a country:");
	$country = &prompt_selection("Your country?",
		default => [ value => $config->param_default("MirrorCountry", $continent) ],
		choices => [
			"No selection - display all mirrors on the continent" => $continent,
			map { /^$continent-/ ? ($keyinfo->{$_},$_) : () } sort keys %$keyinfo
		]
	);
	$config->set_param("MirrorCountry", $country);

} else {
	$country = $config->param("MirrorCountry");
}

	### step 3: mirrors

	if ($obsolete_only) {
		@mirrors_to_choose = keys %obsolete_mirrors;
	} else {
		@mirrors_to_choose = split(/\s+/, $listinfo->{order});
	}

	foreach $mirrorname (@mirrors_to_choose) {
		next if $mirrorname =~ /^\s*$/;

		$mirrorfile = "$libpath/mirror/$mirrorname";
		$mirrortitle = $mirrorname;
		if (exists $listinfo->{lc $mirrorname}) {
			$mirrortitle = $listinfo->{lc $mirrorname};
		}

		$all_mirrors = &read_properties_multival($mirrorfile);

		@mirrors = ();

		if ($obsolete_mirrors{$mirrorname}) {
			$current_prompt = "Current setting (not on current list of mirrors):\n\t\t ";
			$default_response = 2;
		} else {
			$current_prompt = "Current setting:";
			$default_response = 1;
		}
		$def_value = $config->param_default("Mirror-$mirrorname", "");
		if ($def_value) {
			push @mirrors, ( "$current_prompt $def_value" => $def_value );
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
		if ($mirrors_postinstall) {
		$answer = &prompt_selection("Mirror for $mirrortitle?",
						default => [ number => $default_response ],
						choices => \@mirrors,
						timeout => 60 );
	} else {
		$answer = &prompt_selection("Mirror for $mirrortitle?",
						default => [ number => $default_response ],
						choices => \@mirrors );
	}
		$config->set_param("Mirror-$mirrorname", $answer);
	}
	return 0;
}



### EOF
1;
