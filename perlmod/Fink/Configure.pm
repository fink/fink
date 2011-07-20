# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Configure module
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

package Fink::Configure;


###
# Remember to up the $conf_file_compat_version constant below if you add
# a field to the $basepath/etc/fink.conf file.
###

use Fink::Config qw($config $basepath $libpath $distribution);
use Fink::Services qw(&read_properties &read_properties_multival &filename
				&get_options);
use Fink::CLI qw(&prompt &prompt_boolean &prompt_selection &print_breaking);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw(&configure &choose_mirrors $conf_file_compat_version
					  &spotlight_warning);
	%EXPORT_TAGS = ( );			# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }				# module clean-up code here (global destructor)

=head1 NAME

Fink::Configure - handle versioned Fink configuration files

=head1 DESCRIPTION

These functions handle managing changes in the fink.conf file.

=cut

# Compatibility version of the $basepath/etc/fink.conf file.
# Needs to be updated whenever a new field is added to the
# configuration file by code here. This will tell users to 
# rerun fink configure after installing the new fink version.
# (during postinstall.pl)
#
# History:
#  0: Default value, fink < 0.24.0
#  1: Added ConfFileCompatVersion, UseBinaryDist, fink 0.24.0
#  2: Added MaxBuildJobs, fink 0.30.1 (belated bump)
#
our $conf_file_compat_version  = 2;

=head2 Exported Variables

These variables are exported on request.  They are initialized by creating
a Fink::Configure object.

=over 4

=item $conf_file_compat_version

Compatibility version of the F<$basepath/etc/fink.conf> file.
Needs to be updated whenever a new field is added to the
configuration file by code here. This will tell users to 
rerun fink configure after installing the new fink version.

For example, C<1>.

=back

=head2 Functions

=over 4

=item configure

create/change configuration interactively

=cut

sub configure {
	my $just_mirrors = 0;
	get_options('configure', [
		[ 'mirrors|m' => \$just_mirrors, "Only configure the mirrors" ]
	], \@_);
		
	
	print "\n";
	&print_breaking("OK, I'll ask you some questions and update the ".
					"configuration file in '".$config->get_path()."'.");
	print "\n";
	
	choose_misc() unless $just_mirrors;
	choose_mirrors(0, quick => $just_mirrors);

	# set the conf file compatibility version to the current value 
	$config->set_param("ConfFileCompatVersion", $conf_file_compat_version);

	# write configuration
	print "\n";
	&print_breaking("Writing updated configuration to '".$config->get_path().
					"'...");
	$config->save();
}

=item choose_misc

Configure everything but the mirrors

=cut

sub choose_misc {
	my ($otherdir, $verbose);
	my ($proxy_prompt, $proxy, $passive_ftp, $same_for_ftp, $binary_dist);

	# normal configuration
	$otherdir =
		&prompt("In what additional directory should Fink look for downloaded ".
				"tarballs?",
				default => $config->param_default("FetchAltDir", ""));
	if ($otherdir =~ /\S/) {
		$config->set_param("FetchAltDir", $otherdir);
	}

	print "\n";
	{
		my $builddir_default=$config->param_default("Buildpath", "");
		my $builddir =
			&prompt("Which directory should Fink use to build packages? \(If you don't ".
					"know what this means, it is safe to leave it at its default.\)",
					default => $builddir_default);
		while ($builddir =~ /^[^\/]/) {
			$builddir = &prompt("That does not look like a complete (absolute) pathname. Please try again",
								default => $builddir_default);
		}
		if ($builddir =~ /\S/) {
			$config->set_param("Buildpath", $builddir);
		}
	}
	&spotlight_warning();

	print "\n";
	$binary_dist = $config->param_boolean("UseBinaryDist");
	
	my $err;
	if (($err = $config->bindist_check_prefix)
									|| ($err = $config->bindist_check_distro)) {
		print_breaking("$err\n=> Setting UseBinaryDist to 'false'");
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
							"the binary distribution if available?",
							default => $binary_dist);
	}
	$config->set_param("UseBinaryDist", $binary_dist ? "true" : "false");


	print "\n";

	if ($config->param("Distribution") ge "10.7") {
		print_breaking(
			"Note: As of the OS X 10.7 distribution, fink no longer ".
			"has a separate \"unstable\" tree. All development and ".
			"releases happen in the \"stable\" tree, the only public ".
			"tree that exists."
			);
	} elsif ($config->has_param("SelfUpdateMethod")) {
		print_breaking(
			"The \"unstable\" tree contains many packages not present in the \"stable\" ".
			"tree and often has newer versions of those that are present. All package ".
			"updates are tested in \"unstable\" before being approved for \"stable\", ".
			"so \"unstable\" gets new versions and bug-fixes sooner. However, that ".
			"means packages in \"unstable\" can change rapidly and are occasionally ".
			"broken temporarily. In addition, packages from the \"unstable\" tree are ".
			"less likely to be available from bindist servers immediately (if at all)."
			);

		my $trees = $config->param('Trees');
		if (!defined $trees or !length $trees) {
			print_breaking("Could not determine current Trees setting, so cannot alter \"unstable\" setting at this time.");
		} else {
			my @trees = split /\s+/ ,$trees;  # list of the Trees settings
			my $use_unstable = grep { /^unstable(\/|\Z)/ } @trees;  # do we now have unstable?
			if ($use_unstable) {
				$use_unstable = &prompt_boolean(
					"At least some of the \"unstable\" tree appears to ".
					"be activated in your fink now. Do you want to ".
					"keep it activated?",
					default => 1
					);
				if (!$use_unstable) {
					@trees = grep { ! /^unstable(\/|\Z)/ } @trees;  # remove "unstable" ones
					$config->set_param('Trees', join(' ', @trees) );
				}
			} else {
				$use_unstable = &prompt_boolean(
					"The \"unstable\" tree does not appear to be ".
					"activated in your fink now. Do you want to ".
					"activate it?",
					default => 0
					);
				if ($use_unstable) {
					my @trees_add = grep { /^stable(\/|\Z)/ } @trees;  # existing "stable" ones
					map { s/^stable/unstable/ } @trees_add;  # find "unstable" equivs
					push @trees, @trees_add;  # add them
					$config->set_param('Trees', join(' ', @trees) );
					print_breaking("New trees have been added. You ".
								   "should run \"fink selfupdate-rsync\" ".
								   "or \"fink selfupdate-cvs\" in order to ".
								   "download the latest list of packages ".
								   "in the trees.");
				}
			}
		}
	} else {
print_breaking("The selfupdate method has not been set yet, so you ".
"are not yet being asked whether to include the \"unstable\" fink tree. ".
"If you are interested in the \"unstable\" tree, first run \"fink ".
			   "selfupdate\" and then run \"fink configure\" again.");
	}

	$verbose = $config->param_default("Verbose", 1);
	$verbose =
		&prompt_selection("How verbose should Fink be?",
							  default => [value=>$verbose],
							  choices => [
							   "Quiet (do not show download statistics)"   => 0,
							   "Low (do not show tarballs being expanded)" => 1,
							   "Medium (will show almost everything)"      => 2,
							   "High (will show everything)"               => 3
							  ]
							);
	$config->set_param("Verbose", $verbose);

	# proxy settings
	print "\n";
	&print_breaking("Proxy/Firewall settings");

	$proxy_prompt =
		"Enter the URL of the %s proxy to use, or 'none' for no proxy. " .
		"The URL should start with http:// and may contain username, " .
		"password, and/or port specifications. " .
		"Note that this value will be visible to all users on your computer.\n".
		"Example, http://username:password\@hostname:port\n" .
		"Your proxy: ";

	$proxy = $config->param_default("ProxyHTTP", "none");
	$proxy = &prompt(sprintf($proxy_prompt, "HTTP"), default => $proxy);
	if ($proxy =~ /^\s*none\s*$/i) {
		$proxy = "";
	}
	$config->set_param("ProxyHTTP", $proxy);

	if (length $proxy) {
		$same_for_ftp =
			&prompt_boolean("Use the same proxy server for FTP connections?",
							default => 0);
	} else {
		$same_for_ftp = 0;
	}

	if (not $same_for_ftp) {
		$proxy = $config->param_default("ProxyFTP", "none");
		$proxy = &prompt(sprintf($proxy_prompt, "FTP"), default => $proxy);
		if ($proxy =~ /^\s*none\s*$/i) {
			$proxy = "";
		}
	}
	$config->set_param("ProxyFTP", $proxy);

	if ($config->has_param("ProxyPassiveFTP")) {
		$passive_ftp = $config->param_boolean("ProxyPassiveFTP");
	} else {
		# passive FTP is the safe default
		$passive_ftp = 1;
	}
	$passive_ftp =
		&prompt_boolean("Use passive mode FTP transfers (to get through a ".
						"firewall)?", default => $passive_ftp);
	$config->set_param("ProxyPassiveFTP", $passive_ftp ? "true" : "false");

	# clear a non-standard setting
	if ($config->has_param("NoAutoIndex")) {
		if (my $n_a_i = $config->param_boolean("NoAutoIndex")) {
			print "\n";
			chomp($proxy_prompt = <<EOMSG);
The NoAutoIndex feature is currently activated. This feature should
only be used in special circumstances because it can interfere with
updating the lists of available packages. It is recommended that this
feature be deactivated for normal fink use. Do you want to leave it
active?
EOMSG
			$n_a_i = &prompt_boolean($proxy_prompt, default => 0);
			$config->set_param("NoAutoIndex", $n_a_i ? "true" : "false");
		}
	}

	print "\n";
	my $maxbuildjobs_prompt = "Enter the maximum number of simultaneous " .
		"build jobs. In general, Fink will build packages faster on systems " .
		"with multiple CPUs/cores if you allow it to spawn jobs in parallel.";

	my $activecpus = `sysctl -n hw.activecpu 2> /dev/null`;
	if (defined $activecpus) {
		chomp $activecpus;
		if ($activecpus =~ /^\d+$/) {
			$maxbuildjobs_prompt .= " You have $activecpus active CPUs/cores " .
			"on your system.";
		}
	}
	$maxbuildjobs_prompt .= "\nMaximum number of simultaneous build jobs:";
	my $maxbuildjobs = $config->param_default("MaxBuildJobs", $activecpus);
	my $maxbuildjobs_default = $maxbuildjobs;
	$maxbuildjobs = &prompt($maxbuildjobs_prompt,
		default => $maxbuildjobs_default);

	while (!($maxbuildjobs =~ /^\d+$/ && $maxbuildjobs > 0)) {
		$maxbuildjobs = &prompt("Invalid choice. Please try again",
			default => $maxbuildjobs_default);
	}

	$config->set_param("MaxBuildJobs", $maxbuildjobs);
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
				default => 1);
		print "\n";	
		
		$config->set_param("Buildpath", $builddir . ".build") if $response;
		return 1;
	}
	
	return 0;
}	

=item default_location

  my ($continent_code, $country_code) = default_location $keyinfo;

Find the default location for this system. The parameter $keyinfo must be a
hash-ref of the available country and continent codes.

=cut

# If we can't find a real location (eg: if the user is using pure Darwin?)
# use the US since that's where most users are. 
our @fallback_location = ('nam', 'nam-us');

sub default_location {
	my ($keyinfo) = @_;
	
	# Find what the system thinks the country is
	my $syscountry =
		`defaults read /Library/Preferences/.GlobalPreferences Country`;
	chomp $syscountry;
	return @fallback_location if $? != 0 || !defined $syscountry
		|| $syscountry !~ /^[A-Z]{2}$/;
	
	$syscountry = lc $syscountry;
	my @loc = grep { /^[a-z]{3}-$syscountry$/ } keys %$keyinfo;
	return @fallback_location unless scalar(@loc);
	
	$loc[0] =~ /^(\w{3})/;
	return ($1, "$1-$syscountry");
}

=item choose_mirrors

my $didnt_change = choose_mirrors $postinstall, %options;

mirror selection (returns boolean indicating if mirror selections are
unchanged: true means no changes, false means changed)

Options include 'quick' to expedite choices.

=cut

sub choose_mirrors {
	my $mirrors_postinstall = shift; # boolean value, =1 if we've been
					# called from the postinstall script
 					# of the fink-mirrors package
 	my %options = (quick => 0, @_);
 	
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
	
	
	if (!$missing && !$options{quick}) {
		if ($mirrors_postinstall) {
			# called from dpkg postinst script of fink-mirrors pkg
			print "\n";
			$answer = &prompt_boolean("The list of possible mirrors in fink has" .
				" been updated.  Do you want to review and change your choices?",
				default => 0, timeout => 60);
		} else {
			$answer =
				&prompt_boolean("All mirrors are set. Do you want to change them?",
								default => 0);
		}
		if (!$answer) {
			if (%obsolete_mirrors) {
				$obsolete_question = "One or more of your mirrors is set to a value which is not on the current list of mirror choices.  Do you want to leave these as you have set them?";
				if ($mirrors_postinstall) {
					$obsolete_only = !&prompt_boolean($obsolete_question, default => 0, timeout => 60);
				} else {
					$obsolete_only = !&prompt_boolean($obsolete_question, default => 0);
				}
			}
			if (!$obsolete_only) {
				return 1;
			}
		}
	}
	
	if ((!$obsolete_only) or (!$config->has_param("MirrorOrder"))) {	
		$mirror_order = &prompt_selection(
			"What mirror order should fink use when downloading sources?",
			intro   => "The Fink team maintains mirrors known as \"Master\" mirrors, which contain ".
					   "the sources for all fink packages. You can choose to use these mirrors first, ".
					   "last, never, or mixed in with regular mirrors. If you don't care, just select the default.",
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
	my $choose_location = !$obsolete_only && !$options{quick};
	my ($default_continent, $default_country) = default_location $keyinfo;
	if ($choose_location or (!$config->has_param("MirrorContinent"))) {	
		$continent = &prompt_selection("Your continent?",
			intro   => "Choose a continent:",
			default => [ value => $config->param_default("MirrorContinent",
				$default_continent) ],
			choices => [
				map { length($_)==3 ? ($keyinfo->{$_},$_) : () }
					sort { $keyinfo->{$a} cmp $keyinfo->{$b} } keys %$keyinfo
			]
		);
		$config->set_param("MirrorContinent", $continent);
	} else {
		$continent = $config->param("MirrorContinent");
	}

	### step 2: choose a country
	if ($choose_location or (!$config->has_param("MirrorCountry"))) {	
		$country = &prompt_selection("Your country?",
			intro   => "Choose a country:",
			default => [ value => $config->param_default("MirrorCountry",
				$default_country) ], # Fails gracefully if continent wrong for country
			choices => [
				"No selection - display all mirrors on the continent" => $continent,
				map { /^$continent-/ ? ($keyinfo->{$_},$_) : () }
					sort { $keyinfo->{$a} cmp $keyinfo->{$b} } keys %$keyinfo
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
		my %seen;
		
		# Add current setting
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
			$seen{$def_value} = 1;
		}
		
		# Add primary
		if (exists $all_mirrors->{primary}) {
			push @mirrors, map { ( "Primary: $_" => $_ ) }
				grep { !$seen{$_}++ } @{$all_mirrors->{primary}};
		}
		
		# Add local mirrors
		my @places;
		if ($country ne $continent) {	# We chose a country
			@places = ($country, $continent);
		} else {						# We want everything on the continent
			@places = ($continent, sort { $keyinfo->{$a} cmp $keyinfo->{$b} }
				grep { /^$continent-/ } keys %$all_mirrors);
		}
		for my $place (@places) {
			next unless exists $all_mirrors->{$place};
			push @mirrors, map { $keyinfo->{$place} . ": $_" => $_ }
				grep { !$seen{$_}++ } @{$all_mirrors->{$place}};
		}
		
		# Should we limit the number of mirrors?
		
		# Can't pick second result if there isn't one! (2 cuz it's doubled)
		$default_response = 1 unless scalar(@mirrors) > 2;
		
		my @timeout = $mirrors_postinstall ? (timeout => 60) : (); 
		$answer = &prompt_selection("Mirror for $mirrortitle?",
						intro   => "Choose a mirror for '$mirrortitle':",
						default => [ number => $default_response ],
						choices => \@mirrors,
						@timeout,);
		$config->set_param("Mirror-$mirrorname", $answer);
	}

	return 0;
}


=back

=head1 SEE ALSO

L<Fink::Base>

=cut

### EOF
1;
# vim: ts=4 sw=4 noet
