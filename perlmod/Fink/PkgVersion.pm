# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::PkgVersion class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2004 The Fink Package Manager Team
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

package Fink::PkgVersion;
use Fink::Base;
use Fink::Services qw(&filename &execute &execute_script
					  &expand_percent &latest_version
					  &collapse_space &read_properties_var
					  &pkglist2lol &lol2pkglist
					  &file_MD5_checksum &version_cmp
					  &get_arch &get_system_perl_version
					  &get_path &eval_conditional &growl);
use Fink::CLI qw(&print_breaking &prompt_boolean &prompt_selection_new);
use Fink::Config qw($config $basepath $libpath $debarch $buildpath);
use Fink::NetAccess qw(&fetch_url_to_file);
use Fink::Mirror;
use Fink::Package;
use Fink::Status;
use Fink::VirtPackage;
use Fink::Bootstrap qw(&get_bsbase);
use Fink::Command qw(mkdir_p rm_f rm_rf symlink_f du_sk);

use File::Basename qw(&dirname &basename);

use POSIX qw(uname strftime);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter Fink::Base);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw();	# eg: qw($Var1 %Hashit &func3);
	%EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }				# module clean-up code here (global destructor)


### self-initialization
sub initialize {
	my $self = shift;
	my ($pkgname, $epoch, $version, $revision, $filename, $source, $type_hash);
	my ($depspec, $deplist, $dep, $expand, $destdir);
	my ($parentpkgname, $parentdestdir, $parentinvname);
	my ($i, $path, @parts, $finkinfo_index, $section, @splitofffields);
	my $arch = get_arch();

	$self->SUPER::initialize();

	$self->{_name} = $pkgname = $self->param_default("Package", "");
	$self->{_version} = $version = $self->param_default("Version", "0");
	$self->{_revision} = $revision = $self->param_default("Revision", "0");
	$self->{_epoch} = $epoch = $self->param_default("Epoch", "0");

	# multivalue lists were already cleared
	$self->{_type_hash} = $type_hash = Fink::PkgVersion->type_hash_from_string($self->param_default("Type", ""));

	# the following is set by Fink::Package::scan
	$self->{_filename} = $filename = $self->{thefilename};

	# path handling
	if ($filename) {
		@parts = split(/\//, $filename);
		pop @parts;		# remove filename
		$self->{_patchpath} = join("/", @parts);
		for ($finkinfo_index = $#parts;
				 $finkinfo_index > 0 and $parts[$finkinfo_index] ne "finkinfo";
				 $finkinfo_index--) {
			# this loop intentionally left blank
		}
		if ($finkinfo_index <= 0) {
			die "Path \"$filename\" contains no finkinfo directory!\n";
		}
		
		# compute the "section" of this package, e.g. "net", "devel", "crypto"...
		$section = $parts[$finkinfo_index-1]."/";
		if ($finkinfo_index < $#parts) {
			$section = "" if $section eq "main/";
			$section .= join("/", @parts[$finkinfo_index+1..$#parts])."/";
		}
		$self->{_section} = substr($section,0,-1);	 # cut last /
		$parts[$finkinfo_index] = "binary-$debarch";
		$self->{_debpath} = join("/", @parts);
		$self->{_debpaths} = [];
		for ($i = $#parts; $i >= $finkinfo_index; $i--) {
			push @{$self->{_debpaths}}, join("/", @parts[0..$i]);
		}
		
		# determine the package tree ("stable", "unstable", etc.)
				@parts = split(/\//, substr($filename,length("$basepath/fink/dists/")));
		$self->{_tree}	= $parts[0];
	} else {
		# for dummy descriptions generated from dpkg status data alone
		$self->{_patchpath} = "";
		$self->{_section} = "unknown";
		$self->{_debpath} = "";
		$self->{_debpaths} = [];
		
		# assume "binary" tree
		$self->{_tree} = "binary";
	}

	# some commonly used stuff
	$self->{_fullversion} = (($epoch ne "0") ? "$epoch:" : "").$version."-".$revision;
	$self->{_fullname} = $pkgname."-".$version."-".$revision;
	$self->{_debname} = $pkgname."_".$version."-".$revision."_".$debarch.".deb";
	# prepare percent-expansion map
	$destdir = "$buildpath/root-".$self->{_fullname};
	if (exists $self->{parent}) {
		my $parent = $self->{parent};
		$parentpkgname = $parent->{_name};
		$parentdestdir = "$buildpath/root-".$parent->{_fullname};
		$parentinvname = $parent->param_default("package_invariant", $parentpkgname);
	} else {
		$parentpkgname = $pkgname;
		$parentdestdir = $destdir;
		$parentinvname = $self->param_default("package_invariant", $pkgname);
		$self->{_splitoffs} = [];
	}

	$expand = { 'n' => $pkgname,
				'ni'=> $self->param_default("package_invariant", $pkgname),
				'e' => $epoch,
				'v' => $version,
				'r' => $revision,
				'f' => $self->{_fullname},
				'p' => $basepath,
				'd' => $destdir,
				'i' => $destdir.$basepath,
				'm' => $arch,

				'N' => $parentpkgname,
				'Ni'=> $parentinvname,
				'P' => $basepath,
				'D' => $parentdestdir,
				'I' => $parentdestdir.$basepath,

				'a' => $self->{_patchpath},
				'b' => '.'
			};

	foreach (keys %$type_hash) {
		( $expand->{"type_pkg[$_]"} = $expand->{"type_raw[$_]"} = $type_hash->{$_} ) =~ s/\.//g;
	}

	$self->{_expand} = $expand;

	$self->{_bootstrap} = 0;

	# Description is used by 'fink list' so better to get it expanded now
	# also keeps %type_[] out of all list and search fields of pdb
	$self->expand_percent_if_available("Description");

	# from here on we have to distinguish between "real" packages and splitoffs
	if (exists $self->{parent}) {
		# so it's a splitoff
		my ($parent, $field);

		$parent = $self->{parent};
		
		if ($parent->has_param('maintainer')) {
			$self->{'maintainer'} = $parent->{'maintainer'};
		}
		if ($parent->has_param('essential')) {
			$self->{'_parentessential'} = $parent->{'essential'};
		}

		# handle inherited fields
		our @inherited_pkglists =
		 qw(Description DescDetail Homepage License);

		foreach $field (@inherited_pkglists) {
			$field = lc $field;
			if (not $self->has_param($field) and $parent->has_param($field)) {
				$self->{$field} = $parent->{$field};
			}
		}
	} else {
		# implicit "Source" must die
		if (!$self->has_param('Source') and !$self->is_type('dummy') and !$self->is_type('nosource') and !$self->is_type('bundle')) {
			print "\nWarning: file ", $self->get_info_filename, "\nThe implicit \"Source\" feature is deprecated and will be removed soon.\nAdd \"Source: %n-%v.tar.gz\" to assure future compatibility.\n\n";
		}

		# handle splitoff(s)
		@splitofffields = $self->params_matching('SplitOff(?:[2-9]|[1-9]\d+)?');
		if (@splitofffields) {
			# need to keep SplitOff(N) in order
			foreach (map  { $_->[0] }
					 sort { $a->[1] <=> $b->[1] }
					 map  { [ $_, ( (/(\d+)/)[0] || 0 ) ] } @splitofffields
					 ) {
				# form splitoff pkg as its own PkgVersion object
				push @{$self->{_splitoffs}}, $self->add_splitoff($self->param($_),$_);
				delete $self->{$_};  # no need to keep the raw fields in the parent
			}
		}
	}

	if (exists $self->{_splitoffs} and @{$self->{_splitoffs}} > 0) {
		my $splitoff;
		for $splitoff (@{$self->{_splitoffs}}) {
			@{$splitoff->{_relatives}} = ($self, grep {$_->get_name() ne $splitoff->get_name()} @{$self->{_splitoffs}});
		}
		$self->{_relatives} = $self->{_splitoffs};
	}
}

### fields that are package lists need special treatment
### use these accessors instead of param(), has_param(), param_default()
# FIXME-dmacks: need a syntax like foo(-ssl?) that expands to foo|foo-ssl

# fields from which one's own package should be removed
our %pkglist_no_self = ( 'conflicts' => 1,
						 'replaces'  => 1
					   );

sub pkglist {
	my $self = shift;
	my $param_name = lc shift || "";

	$self->expand_percent_if_available($param_name);
	$self->conditional_pkg_list($param_name);
	if (exists $pkglist_no_self{$param_name}) {
		$self->clear_self_from_list($param_name);
	}
	$self->param($param_name);
}

sub pkglist_default {
	my $self = shift;
	my $param_name = lc shift || "";
	my $default_value = shift;

	$self->expand_percent_if_available($param_name);
	$self->conditional_pkg_list($param_name);
	if (exists $pkglist_no_self{$param_name}) {
		$self->clear_self_from_list($param_name);
	}
	$self->param_default($param_name, $default_value);
}

sub has_pkglist {
	my $self = shift;
	my $param_name = lc shift || "";

	$self->expand_percent_if_available($param_name);
	$self->conditional_pkg_list($param_name);
	if (exists $pkglist_no_self{$param_name}) {
		$self->clear_self_from_list($param_name);
	}
	$self->has_param($param_name);
}

### expand percent chars in the given field, if that field exists
### return the expanded form and store it back into the field data

sub expand_percent_if_available {
	my $self = shift;
	my $field = lc shift;

	if ($self->has_param($field)) {
		$self->{$field} = &expand_percent($self->{$field}, $self->{_expand}, $self->get_info_filename." \"$field\"");
	}
}

### expand percent chars in the given field, if that field exists
### return the expanded form but do not store it back into the field data

sub param_expanded {
	my $self = shift;
	return &expand_percent($self->param(@_), $self->{_expand},
		$self->get_info_filename." \"$_[0]\"");
}

# param_default_expanded FIELD, DEFAULT
#
# Expand percent chars in the given field, if that field exists.
# Return the expanded form but do not store it back into the field data.
# If the field doesn't exist, return the default.
sub param_default_expanded {
	my $self = shift;
	return &expand_percent($self->param_default(@_), $self->{_expand},
		$self->get_info_filename." \"$_[0]\"");
}

### Process a Depends (or other field that is a list of packages,
### indicated by $field) to handle conditionals. The field is re-set
### to be conditional-free (remove conditional expressions, remove
### packages for which expression was false). No percent expansion is
### performed (i.e., do it yourself before calling this method).

sub conditional_pkg_list {
	my $self = shift;
	my $field = lc shift;

	my $value = $self->param($field);
	return unless defined $value and length $value;
	return unless $value =~ /(?-:\A|,|\|)\s*\(/;  # short-cut if no conditionals
#	print "conditional_pkg_list for ",$self->get_name,": $field\n";
#	print "\toriginal: '$value'\n";
	my $struct = &pkglist2lol($value);
	foreach (@$struct) {
		foreach (@$_) {
			if (s/^\s*\((.*?)\)\s*(.*)/$2/) {
				# we have a conditional; remove the cond expression
				my $cond = $1;
#				print "\tfound conditional '$cond'\n";
				# if cond is false, clear entire atom
				undef $_ unless &eval_conditional($cond, "$field of ".$self->get_info_filename);
			}
		}
	}
	$value = &lol2pkglist($struct);
#	print "\tnow have: '$value'\n";
	$self->set_param($field, $value);
	return;
}

### Remove our own package name from a given package-list field
### (Conflicts or Replaces, indicated by $field; these fields are
### always AND of single pkgs, no OR clustering). This must be called
### after conditional dependencies are cleared. The field is re-set.

sub clear_self_from_list {
	my $self = shift;
	my $field = lc shift;

	my $value = $self->param($field);
	return unless defined $value and length $value;
	my $pkgname = $self->get_name;
	return unless $value =~ /\Q$pkgname\E/;  # short-cut if we're not listed

	# Approach: break apart comma-delimited list, reassemble only
	# those atoms that don't match.

	$value = join ", ", ( grep { /([a-z0-9.+\-]+)/ ; $1 ne $pkgname } split /,\s*/, $value);
	$self->set_param($field, $value);
}

# Process ConfigureParams (including Type-specific defaults) and
# conditionals, set {_expand}->{c}, and return result.
# Does not change {configureparams}.
#
# NOTE:
#   You must set _expand before calling!
#   You must make sure this method has been called before ever calling
#     expand_percent if it could involve %c!

sub prepare_percent_c {
	my $self = shift;

	my $pct_c;
	if ($self->is_type('perl')) {
		# grab perl version, if present
		my ($perldirectory, $perlarchdir, $perlcmd) = $self->get_perl_dir_arch();

		$pct_c = "PERL=$perlcmd PREFIX=\%p INSTALLPRIVLIB=\%p/lib/perl5$perldirectory INSTALLARCHLIB=\%p/lib/perl5$perldirectory/$perlarchdir INSTALLSITELIB=\%p/lib/perl5$perldirectory INSTALLSITEARCH=\%p/lib/perl5$perldirectory/$perlarchdir INSTALLMAN1DIR=\%p/share/man/man1 INSTALLMAN3DIR=\%p/share/man/man3 INSTALLSITEMAN1DIR=\%p/share/man/man1 INSTALLSITEMAN3DIR=\%p/share/man/man3 INSTALLBIN=\%p/bin INSTALLSITEBIN=\%p/bin INSTALLSCRIPT=\%p/bin ";
	} else {
		$pct_c = "--prefix=\%p ";
	}
	$pct_c .= $self->param_default("ConfigureParams", "");

	# need to expand here so can use %-keys in conditionals
	$pct_c = &expand_percent(
		$pct_c,
		$self->{_expand},
		"ConfigureParams of ".$self->get_info_filename
	);

	$pct_c = $self->conditional_space_list(
		$pct_c,
		"ConfigureParams of ".$self->get_info_filename
	);

	# reprotect "%" b/c %c used in *Script and get_*script() does %-exp
	$pct_c =~ s/\%/\%\%/g;
	$self->{_expand}->{c} = $pct_c;
}

# handle conditionals processing in a list of space-separated atoms
# 
# NOTE:
#   Percent-expansion is *not* performed here; you must do it yourself
#     if necessary before calling this method!

sub conditional_space_list {
	my $self = shift;    # unused
	my $string = shift;  # the string to parse
	my $where = shift;   # used in warning messages

	return $string unless defined $string and $string =~ /\(/; # short-circuit

	use Fink::Text::DelimMatch;

	use Text::ParseWords;    # part of perl5 itself

	# prepare the paren-balancing parser
	my $mc = Fink::Text::DelimMatch->new( '\s*\(\s*', '\s*\)\s*' );
	$mc->quote("'");
	$mc->escape("\\");
	$mc->returndelim(0);
	$mc->keep(0);

	my($stash, $prefix, $cond, $chunk, @save_delim);  # scratches used in loop
	my $result;

	while (defined $string) {
		$stash = $string;  # save in case no parens (parsing clobbers string)

		($prefix, $cond, $string) = $mc->match($string);  # pluck off first paren set
		$result .= $prefix if defined $prefix;  # leading non-paren things
		if (defined $cond) {
			# found a conditional (string in balanced parens)
			if (defined $string) {
				if ($string =~ /^\s*\{/) {
					# grab whole braces-delimited chunk
					@save_delim = $mc->delim( '\s*\{\s*', '\s*\}\s*' );
					($prefix, $chunk, $string) = $mc->match($string);
					$mc->delim(@save_delim);
				} else {
					# grab first word
					# should canibalize parse_line, optimize this specific use
					$chunk = (&parse_line('\s+', 1, $string))[0];
					$string =~ s/^\Q$chunk//;  # already dealt with this now
				}
				if (defined $chunk and $chunk =~ /\S/) {
					# only keep it if conditional is true
					$result .= " $chunk" if &eval_conditional($cond, $where);
				} else {
					print "Conditional \"$cond\" controls nothing in $where!\n";
				}
			} else {
				print "Conditional \"$cond\" controls nothing in $where!\n";
			}
		} else {
			$result .= $stash;
		}
	}

	$result =~ s/^\s*//;
	$result =~ s/\s*$//;
	$result;
}


# returns the requested *Script field (or default value, etc.)
# percent expansion is performed
sub get_script {
	my $self = shift;
	my $field = shift;
	$field = lc $field;

	my $default_script; # Type-based script (%{default_script})
	my $field_value;    # .info field contents

	if ($field eq 'patchscript') {
		return "" if exists $self->{parent};  # shortcut: SplitOffs do not patch
		return "" if $self->is_type('dummy');  # Type:dummy never patch
		return "" if $self->is_type('bundle'); # Type:bundle never patch

		$field_value = $self->param_default($field, '%{default_script}');

		$default_script = "";

	} elsif ($field eq 'compilescript') {
		return "" if exists $self->{parent};  # shortcut: SplitOffs do not compile
		return "" if $self->is_type('bundle'); # Type:bundle never compile

		$field_value = $self->param_default($field, '%{default_script}');

		if ($self->is_type('perl')) {
			my ($perldirectory, $perlarchdir, $perlcmd) = $self->get_perl_dir_arch();
			$default_script =
				"$perlcmd Makefile.PL \%c\n".
				"make\n";
			unless ($self->param_boolean("NoPerlTests")) {
				$default_script .= "make test\n";
			}
		} elsif ($self->is_type('ruby')) {
			my ($rubydirectory, $rubyarchdir, $rubycmd) = $self->get_ruby_dir_arch();
			$default_script =
				"$rubycmd extconf.rb\n".
				"make\n";
		} elsif ($self->is_type('dummy')) {
			$default_script = "";
		} else {
			$default_script =
				"./configure \%c\n".
				"make\n";
		}

	} elsif ($field eq 'installscript') {
		return "" if $self->is_type('dummy');  # Type:dummy never install

		if (exists $self->{parent}) {
			# SplitOffs default to blank script
			$field_value = $self->param_default($field, '');
		} elsif ($self->is_type('bundle')) {
			# Type:bundle always uses predefined script
			$field_value = 
				"/bin/mkdir -p \%i/share/doc/\%n\n".
				"echo \"\%n is a bundle package that doesn't install any files of its own.\" >\%i/share/doc/\%n/README\n";
		} else {
			$field_value = $self->param_default($field, '%{default_script}');
		}

		if ($self->is_type('perl')) {
			# grab perl version, if present
			my ($perldirectory, $perlarchdir) = $self->get_perl_dir_arch();
			$default_script = 
				"make install PREFIX=\%i INSTALLPRIVLIB=\%i/lib/perl5$perldirectory INSTALLARCHLIB=\%i/lib/perl5$perldirectory/$perlarchdir INSTALLSITELIB=\%i/lib/perl5$perldirectory INSTALLSITEARCH=\%i/lib/perl5$perldirectory/$perlarchdir INSTALLMAN1DIR=\%i/share/man/man1 INSTALLMAN3DIR=\%i/share/man/man3 INSTALLSITEMAN1DIR=\%i/share/man/man1 INSTALLSITEMAN3DIR=\%i/share/man/man3 INSTALLBIN=\%i/bin INSTALLSITEBIN=\%i/bin INSTALLSCRIPT=\%i/bin\n";
		} elsif ($self->is_type('bundle')) {
			$default_script = 
				"/bin/mkdir -p \%i/share/doc/\%n\n".
				"echo \"\%n is a bundle package that doesn't install any files of its own.\" >\%i/share/doc/\%n/README\n";
		} else {
			$default_script = "make install prefix=\%i\n";
		} 

	} else {
		# should never get here
		die "Invalid script field for get_script: $field\n";
	}

	# need to pre-expand default_script so not have to change
	# expand_percent() to go a third level deep
	$self->prepare_percent_c;
	$self->{_expand}->{default_script} = &expand_percent(
		$default_script,
		$self->{_expand},
		$self->get_info_filename." ".lc $field
	);
	my $script = &expand_percent($field_value, $self->{_expand},
								 $self->get_info_filename." \"$field\"");
	delete $self->{_expand}->{default_script};  # this key must stay local

	return $script;
}

### add a splitoff package

sub add_splitoff {
	my $self = shift;
	my $splitoff_data = shift;
	my $fieldname = shift;
	my $filename = $self->{_filename};
	my ($properties, $package, $pkgname, @splitoffs);
	
	# get rid of any indention first
	$splitoff_data =~ s/^\s+//gm;
	
	# get the splitoff package name
	$properties = &read_properties_var("$fieldname of \"$filename\"", $splitoff_data);
	$pkgname = $properties->{'package'};
	unless ($pkgname) {
		print "No package name for $fieldname in $filename\n";
	}
	
	# copy version information
	$properties->{'version'} = $self->{_version};
	$properties->{'revision'} = $self->{_revision};
	$properties->{'epoch'} = $self->{_epoch};
	
	# link the splitoff to its "parent" (=us)
	$properties->{parent} = $self;

	# need to inherit (maybe) Type before package gets created
	if (not exists $properties->{'type'}) {
		if (exists $self->{'type'}) {
			$properties->{'type'} = $self->{'type'};
		}
	} elsif ($properties->{'type'} eq "none") {
		delete $properties->{'type'};
	}
	
	# instantiate the splitoff
	@splitoffs = Fink::Package->setup_package_object($properties, $filename);
	
	# return the new object(s)
	return @splitoffs;
}

### merge duplicate package description

sub merge {
	my $self = shift;
	my $dup = shift;
	
	print "Warning! Not a dummy package\n" if $self->is_type('dummy');
	push @{$self->{_debpaths}}, @{$dup->{_debpaths}};
}

### bootstrap helpers

sub enable_bootstrap {
	my $self = shift;
	my $bsbase = shift;
	my $splitoff;

	$self->{_expand}->{p} = $bsbase;
	$self->{_expand}->{d} = "";
	$self->{_expand}->{i} = $bsbase;
	$self->{_expand}->{D} = "";
	$self->{_expand}->{I} = $bsbase;

	$self->{_bootstrap} = 1;
	
	foreach	 $splitoff (@{$self->{_splitoffs}}) {
		$splitoff->enable_bootstrap($bsbase);
	}

}

sub disable_bootstrap {
	my $self = shift;
	my ($destdir);
	my $splitoff;

	$destdir = "$buildpath/root-".$self->{_fullname};
	$self->{_expand}->{p} = $basepath;
	$self->{_expand}->{d} = $destdir;
	$self->{_expand}->{i} = $destdir.$basepath;
	if (exists $self->{parent}) {
		my $parent = $self->{parent};
		my $parentdestdir = "$buildpath/root-".$parent->{_fullname};
		$self->{_expand}->{D} = $parentdestdir;
		$self->{_expand}->{I} = $parentdestdir.$basepath;
	} else {
		$self->{_expand}->{D} = $self->{_expand}->{d};
		$self->{_expand}->{I} = $self->{_expand}->{i};
	};
	
	$self->{_bootstrap} = 0;
	
	foreach	 $splitoff (@{$self->{_splitoffs}}) {
		$splitoff->disable_bootstrap();
	}
}

### get package name, version etc.

sub get_name {
	my $self = shift;
	return $self->{_name};
}

sub get_version {
	my $self = shift;
	return $self->{_version};
}

sub get_revision {
	my $self = shift;
	return $self->{_revision};
}

sub get_fullversion {
	my $self = shift;
	return $self->{_fullversion};
}

sub get_fullname {
	my $self = shift;
	return $self->{_fullname};
}

sub get_filename {
	my $self = shift;
	return $self->{_filename};
}

sub get_debname {
	my $self = shift;
	return $self->{_debname};
}

sub get_debpath {
	my $self = shift;
	return $self->{_debpath};
}

sub get_debfile {
	my $self = shift;
	return $self->{_debpath}."/".$self->{_debname};
}

sub get_section {
	my $self = shift;
	return $self->{_section};
}

# get_instsize DIR
#
# Gets the size of a directory in kilobytes (not bytes!)
sub get_instsize {
	my $self = shift;
	my $path = shift;
	
	my $size = du_sk($path);
	if ( $size =~ /^Error:/ ) {
		die $size;
	}
	return $size;
}

sub get_tree {
	my $self = shift;
	return $self->{_tree};
}

sub get_info_filename {
	my $self = shift;
	return "" unless exists  $self->{thefilename};
	return "" unless defined $self->{thefilename};
	return $self->{thefilename};
}

### other accessors

# get_source_suffices
#
# Returns an ordered list of all "N"s for which there are non-"none" SourceN
# Note that the primary source will always be at the front.
sub get_source_suffices {
	my $self = shift;

	# Cache it
	if (!exists $self->{_source_suffices}) {
		if ( $self->is_type('bundle') || $self->is_type('nosource') || $self->is_type('dummy') || exists $self->{parent} || ( defined $self->param("Source") && lc $self->param("Source") eq 'none' ) ) {
			$self->{_source_suffices} = [];
		} else {
			my @params = $self->params_matching('source([2-9]|[1-9]\d+)');
			map { s/^source//i } @params;
			@params = sort { $a <=> $b } @params;
			@params = grep { defined $self->param("Source$_") && lc $self->param("Source$_") ne 'none' } @params;
			unshift @params, "";
			$self->{_source_suffices} = \@params;
		}
	}
	
	return @{$self->{_source_suffices}};
}

# get_source [ SUFFIX ]
#
# Returns the source for a given SourceN suffix. If no suffix is given,
# returns the primary source.
# On error (eg: nonexistent suffix) returns "none".
# May contain mirror information, don't expect a normal URL. 
sub get_source {
	my $self = shift;
	my $suffix = shift || "";
	
	# Implicit primary source
	if ( $suffix eq "" and !exists $self->{parent} ) {
		my $source = $self->param_default("Source", "\%n-\%v.tar.gz");
		if ($source eq "gnu") {
			$source = "mirror:gnu:\%n/\%n-\%v.tar.gz";
		} elsif ($source eq "gnome") {
			$self->get_version =~ /(^[0-9]+\.[0-9]+)\.*/;
			$source = "mirror:gnome:sources/\%n/$1/\%n-\%v.tar.gz";
		}
		$self->set_param("Source", $source);
	}
	
	return $self->param_default_expanded("Source".$suffix, "none");
}

# get_tarball [ SUFFIX ]
#
# Returns the name of the source tarball for a given SourceN suffix.
# If no suffix is given, returns the primary source tarball's name.
# On error (eg: nonexistent suffix) returns undef.
sub get_tarball {
	my $self = shift;
	my $suffix = shift || "";

	if ($self->has_param("Source".$suffix."Rename")) {
		return $self->param_expanded("Source".$suffix."Rename");
	} else {
		my $tarball = &filename($self->get_source($suffix));
		return undef if $tarball eq 'none';
		return $tarball;
	}
}

# get_checksum [ SUFFIX ]
#
# Returns the checksum of the source tarball for a given SourceN suffix.
# If no suffix is given, returns the primary source tarball's checksum.
# On error (eg: no checksum for the requested suffix) returns undef.
sub get_checksum {
	my $self = shift;
	my $suffix = shift || "";
	
	my $field = "Source".$suffix."-MD5";
	return undef if not $self->has_param($field);
	return $self->param($field);
}

sub get_custom_mirror {
	my $self = shift;
	my $suffix = shift || "";

	if (exists $self->{_custom_mirror}) {
		return $self->{_custom_mirror};
	}

	if ($self->has_param("CustomMirror")) {
		$self->{_custom_mirror} =
			Fink::Mirror->new_from_field($self->param_expanded("CustomMirror"));
	} else {
		$self->{_custom_mirror} = 0;
	}
	return $self->{_custom_mirror};
}

sub get_build_directory {
	my $self = shift;
	my ($dir);

	if (exists $self->{_builddir}) {
		return $self->{_builddir};
	}

	if ($self->is_type('bundle') || $self->is_type('nosource')
			|| lc $self->get_source() eq "none"
			|| $self->param_boolean("NoSourceDirectory")) {
		$self->{_builddir} = $self->get_fullname();
	}
	elsif ($self->has_param("SourceDirectory")) {
		$self->{_builddir} = $self->get_fullname()."/".
			$self->param_expanded("SourceDirectory");
	}
	else {
		$dir = $self->get_tarball(); # never undef b/c never get here if no source
		if ($dir =~ /^(.*)\.tar(\.(gz|z|Z|bz2))?$/) {
			$dir = $1;
		}
		if ($dir =~ /^(.*)\.(tgz|zip)$/) {
			$dir = $1;
		}

		$self->{_builddir} = $self->get_fullname()."/".$dir;
	}

	$self->{_expand}->{b} = "$buildpath/".$self->{_builddir};
	return $self->{_builddir};
}

sub get_splitoffs {
	my $self = shift;
	my $include_parent = shift || 0;
	my $include_self = shift || 0;
	my @list = ();
	my ($splitoff, $parent);

	if (exists $self->{parent}) {
		$parent = $self->{parent};
	} else {
		$parent = $self;
	}

	if ($include_parent) {
		unless ($self eq $parent && not $include_self) {
			push(@list, $parent);
		}
	}

	foreach $splitoff (@{$parent->{_splitoffs}}) {
		unless ($self eq $splitoff && not $include_self) {
			push(@list, $splitoff);
		}
	}

	return @list;
}

# returns whether this fink package is of a given Type:

sub is_type {
	my $self = shift;
	my $type = shift;

	return 0 unless defined $type;
	return 0 unless length $type;
	$type = lc $type;

	if (!exists $self->{_type_hash}) {
		$self->{_type_hash} = $self->type_hash_from_string($self->param_default("Type", ""));
	}

	if (defined $self->{_type_hash}->{$type} and length $self->{_type_hash}->{$type}) {
		return 1;
	}
	return 0;
}

# returns the subtype for a given type, or undef if the type is not
# known for the package

sub get_subtype {
	my $self = shift;
	my $type = shift;

	if (!exists $self->{_type_hash}) {
		$self->{_type_hash} = $self->type_hash_from_string($self->param_default("Type", ""));
	}

	return $self->{_type_hash}->{$type};
}

# given a string representing the Type: field (with no multivalue
# subtype lists), return a ref to a hash of type=>subtype

sub type_hash_from_string {
	shift;	# class method - ignore first parameter
	my $string = shift;
	my $filename = shift;

	my %hash;
	$string =~ s/\s*$//g;  # detritus from multitype parsing
	foreach (split /\s*,\s*/, $string) {
		if (/^(\S+)$/) {
			# no subtype so use type as subtype
			$hash{lc $1} = lc $1;
		} elsif (/^(\S+)\s+(\S+)$/) {
			# have subtype
			$hash{lc $1} = $2;
		} else {
			warn "Bad Type specifier '$_' in $filename\n";
		}
	}
	return \%hash;
}

### generate description

sub format_description {
	my $s = shift;

	# remove last newline (if any)
	chomp $s;
	# replace empty lines with "."
	$s =~ s/^\s*$/\./mg;
	# add leading space
	# (if you change this here, must compensate in Engine::cmd_dumpinfo)
	$s =~ s/^/ /mg;

	return "$s\n";
}

sub format_oneline {
	my $s = shift;
	my $maxlen = shift || 0;

	chomp $s;
	$s =~ s/\s*\n\s*/ /sg;
	$s =~ s/^\s+//g;
	$s =~ s/\s+$//g;

	if ($maxlen && length($s) > $maxlen) {
		$s = substr($s, 0, $maxlen-3)."...";
	}

	return $s;
}

sub get_shortdescription {
	my $self = shift;
	my $limit = shift || 75;
	my ($desc);

	if ($self->has_param("Description")) {
		$desc = &format_oneline($self->param("Description"), $limit);
	} else {
		$desc = "[Package ".$self->get_name()." version ".$self->get_fullversion()."]";
	}
	return $desc;
}

sub get_description {
	my $self = shift;
	my $style = shift || 0;
	my ($desc, $s);

	if ($self->has_param("Description")) {
		$desc = &format_oneline($self->param("Description"), 75);
	} else {
		$desc = "[Package ".$self->get_name()." version ".$self->get_fullversion()."]";
	}
	$desc .= "\n";

	if ($self->has_param("DescDetail")) {
		$desc .= &format_description($self->param("DescDetail"));
	}

	if ($style != 1) {
		if ($self->has_param("DescUsage")) {
			$desc .= " .\n Usage Notes:\n";
			$desc .= &format_description($self->param("DescUsage"));
		}

		if ($self->has_param("Homepage")) {
			$desc .= " .\n Web site: ".&format_oneline($self->param("Homepage"))."\n";
		}

		if ($self->has_param("Maintainer")) {
			$desc .= " .\n Maintainer: ".&format_oneline($self->param("Maintainer"))."\n";
		}
	}

	return $desc;
}

### get installation state

sub is_fetched {
	my $self = shift;
	my ($suffix);

	if ($self->is_type('bundle') || $self->is_type('nosource') ||
			lc $self->get_source() eq "none" ||
			$self->is_type('dummy')) {
		return 1;
	}

	foreach $suffix ($self->get_source_suffices) {
		if (not defined $self->find_tarball($suffix)) {
			return 0;
		}
	}
	return 1;
}

sub is_aptgetable {
	my $self = shift;
	if (Fink::Package->is_in_apt($self->get_name(), $self->get_fullversion())) {
		return 1;
	}
	return 0;
}

sub is_present {
	my $self = shift;

	if (defined $self->find_debfile()) {
		return 1;
	}
	return 0;
}

sub is_installed {
	my $self = shift;

	if ((&version_cmp(Fink::Status->query_package($self->{_name}), '=', $self->get_fullversion())) or
	   (&version_cmp(Fink::VirtPackage->query_package($self->{_name}), '=', $self->get_fullversion()))) {
		return 1;
	}
	return 0;
}

# find_tarball [ SUFFIX ]
#
# Returns the path of the downloaded tarball for a given SourceN suffix.
# If no suffix is given, returns the primary source tarball's path.
# On error (eg: nonexistent suffix) returns undef.
sub find_tarball {
	my $self = shift;
	my $suffix = shift || "";
	my ($archive, $found_archive);
	my (@search_dirs, $search_dir);

	$archive = $self->get_tarball($suffix);
	return undef if !defined $archive;   # bad suffix

	# compile list of dirs to search
	@search_dirs = ( "$basepath/src" );
	if ($config->has_param("FetchAltDir")) {
		push @search_dirs, $config->param("FetchAltDir");
	}

	# search for archive
	foreach $search_dir (@search_dirs) {
		$found_archive = "$search_dir/$archive";
		if (-f $found_archive) {
			return $found_archive;
		}
	}
	return undef;
}

### binary package finding

sub find_debfile {
	my $self = shift;
	my ($path, $fn);

	foreach $path (@{$self->{_debpaths}}, "$basepath/fink/debs") {
		$fn = $path."/".$self->{_debname};
		if (-f $fn) {
			return $fn;
		}
	}
	if ($config->param_boolean("UseBinaryDist") or Fink::Config::get_option("use_binary")) {
		# the colon (':') for the epoch needs to be url encoded to '%3a' since apt-get
		# likes to store the debs in its cache like this.
		# FIXME: add a _encfulldebname variable or similar, to make the next 
		# line look nicer.
		my $debfile = $self->{_name}."_".(($self->{_epoch} ne "0") ? $self->{_epoch}."%3a" : "").$self->{_version}."-".$self->{_revision}."_".$debarch.".deb";
		$fn = "$basepath/var/cache/apt/archives/$debfile";
		if (-f $fn) {
			return $fn;
		}
	}

	return undef;
}

### get dependencies

# usage: @deplist = $self->resolve_depends($include_build, $field, $forceoff);
# where:
#   $self is a PkgVersion object
#   $include_build indicates what type of dependencies one wants:
#     0 - return runtime dependencies only (default if undef)
#     1 - return runtime & build dependencies
#     2 - return build dependencies only
#   $field is either "depends" or "conflicts" (case-insensitive)
#   $forceoff is a boolean (default is false) that indicates...something
#   @deplist is list of refs to lists of PkgVersion objects
#     @deplist joins the referenced lists as logical AND
#     each referenced list is joined as logical OR
#     In "depends" mode, must have at least one of each sublist installed
#     In "conflicts" mode, must have none of any sublist installed
#     (but makes no sense to have logical OR in a *Conflicts field)

sub resolve_depends {
	my $self = shift;
	my $include_build = shift || 0;
	my $field = shift;
	my $forceoff = shift || 0;

	my @speclist;   # list of logical OR clusters (strings) of pkg specifiers
	my $altspecs;   # iterator for looping through @speclist
	my @altspec;    # list of pkg specifiers (strings) in a logical OR cluster
	my $depspec;    # iterator for looping through @altspec
	my ($depname, $versionspec); # components of a single pkg specifier 
	my $package;    # Package object for a $depname
	my $altlist;    # ref to list of PkgVersion objects meeting an OR cluster
	my @deplist;    # list of lists of PkgVersion objects to be returned

	my ($splitoff, $idx, $split_idx); # used for merging in splitoff-pkg data
	my ($found, $loopcount); # status while looping through an OR cluster
	my $oper;       # used in error and warning messages

	if (lc($field) eq "conflicts") {
		$oper = "conflict";
	} elsif (lc($field) eq "depends") {
		$oper = "dependency";
	}

	@deplist = ();

	$idx = 0;
	$split_idx = 0;

	# If this is a splitoff, and we are asked for build depends, add the build deps
	# of the master package to the list.
	if ($include_build and exists $self->{parent}) {
		push @deplist, ($self->{parent})->resolve_depends(2, $field, $forceoff);
		if ($include_build == 2) {
			# The pure build deps of a splitoff are equivalent to those of the parent.
			return @deplist;
		}
	}
	
	# First, add all regular dependencies to the list.
	if (lc($field) ne "conflicts") {
		# FIXME: Right now we completely ignore 'Conflicts' in the dep engine.
		# We leave handling them to dpkg. That is somewhat ugly, though, because it
		# means that 'Conflicts' are not automatically 'BuildConflicts' (i.e. the
		# behavior differs from 'Depends'). 
		# But right now, enabling conflicts would cause update problems (e.g.
		# when switching between 'wget' and 'wget-ssl')
		@speclist = split(/\s*\,\s*/, $self->pkglist_default($field, ""));
	}

	if (lc($field) ne "conflicts") {
		# With this primitive form of @speclist, we verify that the "BuildDependsOnly"
		# declarations have not been violated (of course we only do that when generating
		# a 'depends' list, not for 'conflicts').
		foreach $altspecs (@speclist){
			## Determine if it has a multi type depends line thus
			## multi pkgs can satisfy the depend and it shouldn't
			## warn if certain ones aren't found, as long as any one of them is
			@altspec = split(/\s*\|\s*/, $altspecs);
			$loopcount = 0;
			$found = 0;
			BUILDDEPENDSLOOP: foreach $depspec (@altspec) {
				$loopcount++;
				if ($depspec =~ /^\s*([0-9a-zA-Z.\+-]+)\s*\((.+)\)\s*$/) {
					$depname = $1;
					$versionspec = $2;
				} elsif ($depspec =~ /^\s*([0-9a-zA-Z.\+-]+)\s*$/) {
					$depname = $1;
					$versionspec = "";
				} else {
					die "Illegal spec format: $depspec\n";
				}
				$package = Fink::Package->package_by_name($depname);
				$found = 1 if defined $package;
				if ((Fink::Config::verbosity_level() > 2 && not defined $package) || ($forceoff && ($loopcount >= scalar(@altspec) && $found == 0))) {
					print "WARNING: While resolving $oper \"$depspec\" for package \"".$self->get_fullname()."\", package \"$depname\" was not found.\n";
				}
				if (not defined $package) {
					next BUILDDEPENDSLOOP;
				}

				if (lc($field) eq "depends" && Fink::Config::verbosity_level() > 1) {
					# only bother to check for BuildDependsOnly
					# violations if we are more verbose than default

					foreach my $dependent ($package->get_all_providers()) {
						# loop through all PkgVersion that supply $pkg

						if ($dependent->param_boolean("BuildDependsOnly")) {
							# whine if BDO violation
							my $dep_providername = $dependent->get_name();
							print "\nWARNING: The package " . $self->get_name() . " Depends on $depname";
							if ($dep_providername ne $depname) {  # virtual pkg
								print "\n\t (which is provided by $dep_providername)";
							}
							print ",\n\t but $depname only allows things to BuildDepend on it.\n\n";
						}
					}
				}
			}
		}
	}

	# now we continue to assemble the larger @speclist
	if ($include_build) {
		# Add build time dependencies to the spec list
		push @speclist,
			split(/\s*\,\s*/, $self->pkglist_default("Build".$field, ""));

		# If this is a master package with splitoffs, and build deps are requested,
		# then add to the list the deps of all our splitoffs.
		# We remember the offset at which we added these in $split_idx, so that we
		# can remove any inter-splitoff deps that would otherwise be introduced by this.
		$split_idx = @speclist;
		unless (lc($field) eq "conflicts") {
			foreach	 $splitoff (@{$self->{_splitoffs}}) {
				push @speclist,
				split(/\s*\,\s*/, $splitoff->pkglist_default($field, ""));
			}
		}
	}

	SPECLOOP: foreach $altspecs (@speclist) {
		$altlist = [];
		@altspec = split(/\s*\|\s*/, $altspecs);
		$found = 0;
		$loopcount = 0;
		foreach $depspec (@altspec) {
			$loopcount++;
			if ($depspec =~ /^\s*([0-9a-zA-Z.\+-]+)\s*\((.+)\)\s*$/) {
				$depname = $1;
				$versionspec = $2;
			} elsif ($depspec =~ /^\s*([0-9a-zA-Z.\+-]+)\s*$/) {
				$depname = $1;
				$versionspec = "";
			} else {
				die "Illegal spec format: $depspec\n";
			}

			if ($include_build and @{$self->{_splitoffs}} > 0 and
				 ($idx >= $split_idx or $include_build == 2)) {
				# To prevent circular refs in the build dependency graph, we have to
				# remove all our splitoffs from the graph. Exception: any splitoffs
				# this master depends on directly are not filtered. Exception from the
				# exception: if we were called by a splitoff to determine the "meta
				# dependencies" of it, then we again filter out all splitoffs.
				# If you've read till here without mental injuries, congrats :-)
				next SPECLOOP if ($depname eq $self->{_name});
				foreach	 $splitoff (@{$self->{_splitoffs}}) {
					next SPECLOOP if ($depname eq $splitoff->get_name());
				}
			}

			$package = Fink::Package->package_by_name($depname);

			$found = 1 if defined $package;
			if ((Fink::Config::verbosity_level() > 2 && not defined $package) || ($forceoff && ($loopcount >= scalar(@altspec) && $found == 0))) {
				print "WARNING: While resolving $oper \"$depspec\" for package \"".$self->get_fullname()."\", package \"$depname\" was not found.\n";
			}
			if (not defined $package) {
				next;
			}

			push(@{$package->{_versionspecs}}, $versionspec) unless ($versionspec =~ /^\s*$/);

			if ($versionspec) {
				push @$altlist, $package->get_matching_versions($versionspec);
			} else {
				push @$altlist, $package->get_all_providers();
			}
		}
		if (scalar(@$altlist) <= 0 && lc($field) ne "conflicts") {
			die "Can't resolve $oper \"$altspecs\" for package \"".$self->get_fullname()."\" (no matching packages/versions found)\n";
		}
		push @deplist, $altlist;
		$idx++;
	}

	return @deplist;
}

sub resolve_conflicts {
	my $self = shift;
	my ($confname, $package, @conflist);

	# conflict with other versions of the same package
	# this here includes ourselves, it is treated The Right Way
	# by other routines
	@conflist = Fink::Package->package_by_name($self->get_name())->get_all_versions();

	foreach $confname (split(/\s*\,\s*/,$self->pkglist_default("Conflicts", ""))) {
		$package = Fink::Package->package_by_name($confname);
		if (not defined $package) {
			die "Can't resolve anti-dependency \"$confname\" for package \"".$self->get_fullname()."\"\n";
		}
		push @conflist, [ $package->get_all_providers() ];
	}

	return @conflist;
}

sub get_binary_depends {
	my $self = shift;
	my ($depspec);

	# TODO: modify dependency list on the fly to account for minor
	#	 library versions

	$depspec = $self->pkglist_default("Depends", "");

	return &collapse_space($depspec);
}


### find package and version by matching a specification

sub match_package {
	shift;	# class method - ignore first parameter
	my $s = shift;
	my $quiet = shift || 0;

	my ($pkgname, $package, $version, $pkgversion);
	my ($found, @parts, $i, @vlist, $v, @rlist);

	if (Fink::Config::verbosity_level() < 3) {
		$quiet = 1;
	}

	# first, search for package
	$found = 0;
	$package = Fink::Package->package_by_name($s);
	if (defined $package) {
		$found = 1;
		$pkgname = $package->get_name();
		$version = "###";
	} else {
		# try to separate version from name (longest match)
		@parts = split(/-/, $s);
		for ($i = $#parts - 1; $i >= 0; $i--) {
			$pkgname = join("-", @parts[0..$i]);
			$version = join("-", @parts[$i+1..$#parts]);
			$package = Fink::Package->package_by_name($pkgname);
			if (defined $package) {
				$found = 1;
				last;
			}
		}
	}
	if (not $found) {
		print "no package found for \"$s\"\n"
			unless $quiet;
		return undef;
	}

	# we now have the package name in $pkgname, the package
	# object in $package, and the
	# still to be matched version (or "###") in $version.
	if ($version eq "###") {
		# find the newest version

		$version = &latest_version($package->list_versions());
		if (not defined $version) {
			# there's nothing we can do here...
			die "no version info available for $pkgname\n";
		}
	} elsif (not defined $package->get_version($version)) {
		# try to match the version

		@vlist = $package->list_versions();
		@rlist = ();
		foreach $v (@vlist)	 {
			if ($package->get_version($v)->get_version() eq $version) {
				push @rlist, $v;
			}
		}
		$version = &latest_version(@rlist);
		if (not defined $version) {
			# there's nothing we can do here...
			die "no matching version found for $pkgname\n";
		}
	}

	return $package->get_version($version);
}

###
### PHASES
###

### fetch_deb

sub phase_fetch_deb {
	my $self = shift;
	my $conditional = shift || 0;
	my $dryrun = shift || 0;

	# check if $basepath is really '/sw' since the debs are built with 
	# '/sw' hardcoded
	if (not $basepath eq '/sw') {
		print "\n";
		&print_breaking("ERROR: Downloading packages from the binary distribution ".
		                "is currently only possible if Fink is installed at '/sw'!.");
		die "Downloading the binary package '" . $self->get_debname() . "' failed.\n";
	}

	if (not $conditional) {
		# delete already downloaded deb
		my $found_deb = $self->find_debfile();
		if ($found_deb) {
			rm_f $found_deb;
		}
	}
	$self->fetch_deb(0, 0, $dryrun);
}

# fetch_deb [ TRIES ], [ CONTINUE ], [ DRYRUN ]
#
# Unconditionally download the deb, dying on failure.
sub fetch_deb {
	my $self = shift;
	my $tries = shift || 0;
	my $continue = shift || 0;
	my $dryrun = shift || 0;

	if (Fink::Config::verbosity_level() > 2) {
		print "Downloading " . $self->get_debname() . " from binary dist.\n";
	}
	my $aptcmd = "$basepath/bin/apt-get ";
	if (Fink::Config::verbosity_level() == 0) {
		$aptcmd .= "-qq ";
	}
	elsif (Fink::Config::verbosity_level() < 2) {
		$aptcmd .= "-q ";
	}
	if($dryrun) {
		$aptcmd .= "--dry-run ";
	}
	$aptcmd .= "--ignore-breakage --download-only install " . $self->get_name() . "=" .$self->get_fullversion();
	if (&execute($aptcmd)) {
		if (0) {
		print "\n";
		&print_breaking("Downloading '".$self->get_debname()."' failed. ".
		                "There can be several reasons for this:");
		&print_breaking("The server is too busy to let you in or ".
		                "is temporarily down. Try again later.",
		                1, "- ", "	");
		&print_breaking("There is a network problem. If you are ".
		                "behind a firewall you may want to check ".
		                "the proxy and passive mode FTP ".
		                "settings. Then try again.",
		                1, "- ", "	");
		&print_breaking("The file was removed from the server or ".
		                "moved to another directory. The package ".
		                "description must be updated.");
		print "\n";
		}
		if($dryrun) {
			if ($self->has_param("Maintainer")) {
				print ' "'.$self->param("Maintainer") . "\"\n";
			}
		} else {
			die "Downloading the binary package '" . $self->get_debname() . "' failed.\n";
		}
	}
}

### fetch

sub phase_fetch {
	my $self = shift;
	my $conditional = shift || 0;
	my $dryrun = shift || 0;
	my ($suffix);

	if (exists $self->{parent}) {
		($self->{parent})->phase_fetch($conditional, $dryrun);
		return;
	}
	if ($self->is_type('bundle') || $self->is_type('nosource') ||
			lc $self->get_source() eq "none" ||
			$self->is_type('dummy')) {
		return;
	}

	foreach $suffix ($self->get_source_suffices) {
		if (not $conditional or not defined $self->find_tarball($suffix)) {
			$self->fetch_source($suffix,0,0,0,$dryrun);
		}
	}
}

# fetch_source SUFFIX, [ TRIES ], [ CONTINUE ], [ NOMIRROR ], [ DRYRUN ]
#
# Unconditionally download the source for a given SourceN suffix, dying on
# failure.
sub fetch_source {
	my $self = shift;
	my $suffix = shift;
	my $tries = shift || 0;
	my $continue = shift || 0;
	my $nomirror = shift || 0;
	my $dryrun = shift || 0;
	my ($url, $file, $checksum);

	chdir "$basepath/src";

	$url = $self->get_source($suffix);
	$file = $self->get_tarball($suffix);
	if($self->has_param("license")) {
		if($self->param("license") =~ /Restrictive\s*$/) {
			$nomirror = 1;
		} 
	}
	
	$checksum = $self->get_checksum($suffix);
	
	if($dryrun) {
		return if $url eq $file; # just a simple filename
		print "$file ", (defined $checksum ? $checksum : "-");
	} else {
		if(not defined $checksum) {	
			print "WARNING: No MD5 specified for Source".$suffix.
							" of package ".$self->get_fullname();
			if ($self->has_param("Maintainer")) {
				print ' Maintainer: '.$self->param("Maintainer") . "\n";
			} else {
				print "\n";
			}		
		}
	}
	
	if (&fetch_url_to_file($url, $file, $self->get_custom_mirror($suffix), 
						   $tries, $continue, $nomirror, $dryrun, undef, $checksum)) {

		if (0) {
		print "\n";
		&print_breaking("Downloading '$file' from the URL '$url' failed. ".
						"There can be several reasons for this:");
		&print_breaking("The server is too busy to let you in or ".
						"is temporarily down. Try again later.",
						1, "- ", "	");
		&print_breaking("There is a network problem. If you are ".
						"behind a firewall you may want to check ".
						"the proxy and passive mode FTP ".
						"settings. Then try again.",
						1, "- ", "	");
		&print_breaking("The file was removed from the server or ".
						"moved to another directory. The package ".
						"description must be updated.",
						1, "- ", "	");
		&print_breaking("The package specifies an incorrect checksum ".
						"for the file.",
						1, "- ", "	");
		&print_breaking("In any case, you can download '$file' manually and ".
						"put it in '$basepath/src', then run fink again with ".
						"the same command. If you have checksum problems, ".
						"make sure you have  updated your package ".
						"recently; contact the package maintainer.");
		print "\n";
		}
		if($dryrun) {
			if ($self->has_param("Maintainer")) {
				print ' "'.$self->param("Maintainer") . "\"\n";
			}
		} else {
			die "file download failed for $file of package ".$self->get_fullname()."\n";
		}
	}
}

### unpack

sub phase_unpack {
	my $self = shift;
	my ($archive, $found_archive, $bdir, $destdir, $unpack_cmd);
	my ($suffix, $verbosity, $answer, $tries, $checksum, $continue);
	my ($renamefield, @renamefiles, $renamefile, $renamelist, $expand);
	my ($tarcommand, $tarflags, $cat, $gzip, $bzip2, $unzip, $found_archive_sum);

	if ($self->is_type('bundle') || $self->is_type('dummy')) {
		return;
	}
	if (exists $self->{parent}) {
		($self->{parent})->phase_unpack();
		return;
	}

	my ($gcc);
	my %gcchash = ('2.95.2' => '2', '2.95' => '2', '3.1' => '3', '3.3' => '3.3', '4.0.0' => '3.3');

	if ($self->has_param("GCC")) {
		$gcc = $self->param("GCC");
		chomp(my $gcc_select = `gcc_select`);
		if (not $gcc_select =~ s/^.*gcc version (\S+)\s+.*$/$1/gs) {
			$gcc_select = 'an unknown version';
		}
		if (not exists $gcchash{$gcc_select}) {
			$gcchash{$gcc_select} = $gcc_select;
		}
		if ($gcchash{$gcc_select} ne $gcc) {
			die <<END;

This package must be compiled with GCC $gcc, but you currently have $gcc_select selected.
To correct this problem, run the command:

	sudo gcc_select $gcchash{$gcc}

You may need to install a more recent version of the Developer Tools to be able
to do so.

END
		}
	}

	$bdir = $self->get_fullname();

	$verbosity = "";
	if (Fink::Config::verbosity_level() > 1) {
		$verbosity = "v";
	}

	# remove dir if it exists
	chdir "$buildpath";
	if (-e $bdir) {
		rm_rf $bdir or
			die "can't remove existing directory $bdir\n";
	}

	if ($self->is_type('nosource') || lc $self->get_source() eq "none") {
		$destdir = "$buildpath/$bdir";
		mkdir_p $destdir or
			die "can't create directory $destdir\n";
		return;
	}

	$tries = 0;
	foreach $suffix ($self->get_source_suffices) {
		$archive = $self->get_tarball($suffix);

		# search for archive, try fetching if not found
		$found_archive = $self->find_tarball($suffix);
		if (not defined $found_archive or $tries > 0) {
			$self->fetch_source($suffix, $tries, $continue);
			$continue = 0;
			$found_archive = $self->find_tarball($suffix);
		}
		if (not defined $found_archive) {
			die "can't find source file $archive for package ".$self->get_fullname()."\n";
		}
		
		# verify the MD5 checksum, if specified
		$checksum = $self->get_checksum($suffix);
		$found_archive_sum = &file_MD5_checksum($found_archive);
		if (defined $checksum) { # Checksum was specified
		# compare to the MD5 checksum of the tarball
			if ($checksum ne $found_archive_sum) {
				# mismatch, ask user what to do
				$tries++;
				&print_breaking("The checksum of the file $archive of package ".
								$self->get_fullname()." is incorrect. The most likely ".
								"cause for this is a corrupted or incomplete download\n".
								"Expected: $checksum \nActual: $found_archive_sum \n".
								"It is recommended that you download it ".
								"again. How do you want to proceed?");
				$answer = &prompt_selection_new("Make your choice: ",
								[ value => ($tries >= 3) ? "error" : "redownload" ],
								( "Give up" => "error",
								  "Delete it and download again" => "redownload",
								  "Assume it is a partial download and try to continue" => "continuedownload",
								  "Don't download, use existing file" => "continue" ) );
				if ($answer eq "redownload") {
					rm_f $found_archive;
					# Axel leaves .st files around for partial files, need to remove
					if($config->param_default("DownloadMethod") =~ /^axel/)
					{
									rm_f "$found_archive.st";
					}
					redo;		# restart loop with same tarball
				} elsif($answer eq "error") {
					die "checksum of file $archive of package ".$self->get_fullname()." incorrect\n";
				} elsif($answer eq "continuedownload") {
					$continue = 1;
					redo;		# restart loop with same tarball			
				}
			}
		} else {
		# No checksum was specifed in the .info file, die die die
			die "No MD5 specifed for Source$suffix of ".$self->get_fullname()." I got a checksum of $found_archive_sum \n";
		}

		# Determine the name of the TarFilesRename in the case of multi tarball packages
		$renamefield = "Tar".$suffix."FilesRename";

		$renamelist = "";

		# Determine the rename list (if any)
		$tarflags = "-x${verbosity}f -";

		# Note: the Apple-supplied /usr/bin/gnutar in versions 10.2 and
		# earlier does not know about the flags --no-same-owner and
		# --no-same-permissions.  Therefore, we do not use these in
		# the "default" situation (which should only occur during bootstrap).

		my $permissionflags = " --no-same-owner --no-same-permissions";
		$tarcommand = "/usr/bin/gnutar $tarflags"; # Default to Apple's GNU Tar
		if ($self->has_param($renamefield)) {
			@renamefiles = split(/\s+/, $self->param($renamefield));
			foreach $renamefile (@renamefiles) {
				$renamefile = &expand_percent($renamefile, $expand, $self->get_info_filename." \"$renamefield\"");
				if ($renamefile =~ /^(.+)\:(.+)$/) {
					$renamelist .= " -s ,$1,$2,";
				} else {
					$renamelist .= " -s ,${renamefile},${renamefile}_tmp,";
				}
			}
			$tarcommand = "/bin/pax -r${verbosity}"; # Use pax for extracting with the renaming feature
		} elsif ( -e "$basepath/bin/tar" ) {
			$tarcommand = "$basepath/bin/tar $tarflags $permissionflags"; # Use Fink's GNU Tar if available
		}
		$bzip2 = "bzip2";
		$unzip = "unzip";
		$gzip = "gzip";
		$cat = "/bin/cat";

		# Determine unpack command
		$unpack_cmd = "cp $found_archive .";
		if ($archive =~ /[\.\-]tar\.(gz|z|Z)$/ or $archive =~ /\.tgz$/) {
			$unpack_cmd = "$gzip -dc $found_archive | $tarcommand $renamelist";
		} elsif ($archive =~ /[\.\-]tar\.bz2$/) {
			$unpack_cmd = "$bzip2 -dc $found_archive | $tarcommand $renamelist";
		} elsif ($archive =~ /[\.\-]tar$/) {
			$unpack_cmd = "$cat $found_archive | $tarcommand $renamelist";
		} elsif ($archive =~ /\.zip$/) {
			$unpack_cmd = "$unzip -o $found_archive";
		}
	
		# calculate destination directory
		$destdir = "$buildpath/$bdir";
		if ($suffix ne "") {	# Primary sources have no special extract dir
			my $extractparam = "Source".$suffix."ExtractDir";
			if ($self->has_param($extractparam)) {
				$destdir .= "/".$self->param_expanded($extractparam);
			}
		}

		# create directory
		if (! -d $destdir) {
			mkdir_p $destdir or
				die "can't create directory $destdir\n";
		}

		# unpack it
		chdir $destdir;
		if (&execute($unpack_cmd)) {
			$tries++;

			# FIXME: this is not the likely problem now since we already checked MD5
			$answer =
				&prompt_boolean("Unpacking the file $archive of package ".
								$self->get_fullname()." failed. The most likely ".
								"cause for this is a corrupted or incomplete ".
								"download. Do you want to delete the tarball ".
								"and download it again?",
								($tries >= 3) ? 0 : 1);
			if ($answer) {
				rm_f $found_archive;
				redo;		# restart loop with same tarball
			} else {
				die "unpacking file $archive of package ".$self->get_fullname()." failed\n";
			}
		}

		$tries = 0;
	}
}

### patch

sub phase_patch {
	my $self = shift;
	my ($dir, $patch_script, $cmd, $patch, $subdir);

	if ($self->is_type('bundle') || $self->is_type('dummy')) {
		return;
	}
	if (exists $self->{parent}) {
		($self->{parent})->phase_patch();
		return;
	}

	$dir = $self->get_build_directory();
	if (not -d "$buildpath/$dir") {
		die "directory $buildpath/$dir doesn't exist, check the package description\n";
	}
	chdir "$buildpath/$dir";

	$patch_script = "";

	### copy host type scripts (config.guess and config.sub) if required

	if ($self->param_boolean("UpdateConfigGuess")) {
		$patch_script .=
			"cp -f $libpath/update/config.guess .\n".
			"cp -f $libpath/update/config.sub .\n";
	}
	if ($self->has_param("UpdateConfigGuessInDirs")) {
		foreach $subdir (split(/\s+/, $self->param("UpdateConfigGuessInDirs"))) {
			next unless $subdir;
			$patch_script .=
				"cp -f $libpath/update/config.guess $subdir\n".
				"cp -f $libpath/update/config.sub $subdir\n";
		}
	}

	### copy libtool scripts (ltconfig and ltmain.sh) if required

	if ($self->param_boolean("UpdateLibtool")) {
		$patch_script .=
			"cp -f $libpath/update/ltconfig .\n".
			"cp -f $libpath/update/ltmain.sh .\n";
	}
	if ($self->has_param("UpdateLibtoolInDirs")) {
		foreach $subdir (split(/\s+/, $self->param("UpdateLibtoolInDirs"))) {
			next unless $subdir;
			$patch_script .=
				"cp -f $libpath/update/ltconfig $subdir\n".
				"cp -f $libpath/update/ltmain.sh $subdir\n";
		}
	}

	### copy po/Makefile.in.in if required

	if ($self->param_boolean("UpdatePoMakefile")) {
		$patch_script .=
			"cp -f $libpath/update/Makefile.in.in po/\n";
	}

	### run what we have so far
	$self->run_script($patch_script, "patching (Update* flags)", 0);
	$patch_script = "";

	### patches specified by filename
	if ($self->has_param("Patch")) {
		foreach $patch (split(/\s+/,$self->param("Patch"))) {
			$patch_script .= "patch -p1 <\%a/$patch\n";
		}
	}
	$self->run_script($patch_script, "patching (patchfiles)", 0);

	### Deal with PatchScript field
	$self->run_script($self->get_script("PatchScript"), "patching", 1);
}

### compile

sub phase_compile {
	my $self = shift;
	my ($dir, $compile_script, $cmd);

	if ($self->is_type('bundle')) {
		return;
	}
	if ($self->is_type('dummy') and not $self->has_param('CompileScript')) {
		die "compile phase: can't build ".$self->get_fullname().
				" because no package description is available\n";
	}
	if (exists $self->{parent}) {
		($self->{parent})->phase_compile();
		return;
	}

	if (!$self->is_type('dummy')) {
		# dummy packages do not actually compile (so no build dir),
		# but they can have a CompileScript to run
		$dir = $self->get_build_directory();
		if (not -d "$buildpath/$dir") {
			die "directory $buildpath/$dir doesn't exist, check the package description\n";
		}
		chdir "$buildpath/$dir";
	}

	### construct CompileScript and execute it
	$self->run_script($self->get_script("CompileScript"), "compiling", 1);
}

### install

sub phase_install {
	my $self = shift;
	my $do_splitoff = shift || 0;
	my ($dir, $install_script, $cmd, $bdir);

	if ($self->is_type('dummy')) {
		die "install phase: can't build ".$self->get_fullname().
				" because no package description is available\n";
	}
	if (exists $self->{parent} and not $do_splitoff) {
		($self->{parent})->phase_install();
		return;
	}
	if (not $self->is_type('bundle')) {
		if ($do_splitoff) {
			$dir = ($self->{parent})->get_build_directory();
		} else {
			$dir = $self->get_build_directory();
		}
		if (not -d "$buildpath/$dir") {
			die "directory $buildpath/$dir doesn't exist, check the package description\n";
		}
		chdir "$buildpath/$dir";
	}

	# generate installation script

	$install_script = "";
	unless ($self->{_bootstrap}) {
		$install_script .= "/bin/rm -rf \%d\n";
	}
	$install_script .= "/bin/mkdir -p \%i\n";
	unless ($self->{_bootstrap}) {
		$install_script .= "/bin/mkdir -p \%d/DEBIAN\n";
	}
	# Run the script part we have so far
	$self->run_script($install_script, "installing", 0);
	$install_script = ""; # reset it
	# Now run the actual InstallScript
	$self->run_script($self->get_script("InstallScript"), "installing", 1);
	if (!$self->is_type('bundle')) {
		# Handle remaining fields that affect installation
		if ($self->param_boolean("UpdatePOD")) {
			# grab perl version, if present
			my ($perldirectory, $perlarchdir) = $self->get_perl_dir_arch();

			$install_script .= 
				"/bin/mkdir -p \%i/share/podfiles$perldirectory\n".
				"for i in `find \%i -name perllocal.pod`; do /bin/cat \$i | sed -e s,\%i/lib/perl5,\%p/lib/perl5, >> \%i/share/podfiles$perldirectory/perllocal.\%n.pod; /bin/rm -rf \$i; done;\n";
		}
	}

	# splitoff 'Files' field
	if ($do_splitoff and $self->has_param("Files")) {
		my $files = $self->conditional_space_list(
			$self->param_expanded("Files"),
			"Files of ".$self->get_fullname()." in ".$self->get_info_filename
		);

		my (@files, $file, $source, $target, $target_dir);

		@files = split(/\s+/, $files);
		foreach $file (@files) {
			$file =~ s/\%/\%\%/g;   # reprotect for later %-expansion
			if ($file =~ /^(.+)\:(.+)$/) {
				$source = $1;
				$target = $2;
			} else {
				$source = $file;
				$target = $file;
			}
			# If the path starts with a slash, assume it is meant to be global
			# and base it upon %D, otherwise treat it as relative to %I
			if ($source =~ /^\//) {
				$source = "%D$source";
			} else {
				$source = "%I/$source";
			}
			# Now the same for the target (but use %d and %i).
			if ($target =~ /^\//) {
				$target = "%d$target";
			} else {
				$target = "%i/$target";
			}

			$target_dir = dirname($target);
			$install_script .= "\n/usr/bin/install -d -m 755 $target_dir";
			$install_script .= "\n/bin/mv $source $target_dir/";
		}
	}

	# generate commands to install documentation files
	if ($self->has_param("DocFiles")) {
		my (@docfiles, $docfile, $docfilelist);
		$install_script .= "\n/usr/bin/install -d -m 755 %i/share/doc/%n";

		@docfiles = split(/\s+/, $self->param("DocFiles"));
		$docfilelist = "";
		foreach $docfile (@docfiles) {
			if ($docfile =~ /^(.+)\:(.+)$/) {
				$install_script .= "\n/usr/bin/install -c -p -m 644 $1 %i/share/doc/%n/$2";
			} else {
				$docfilelist .= " $docfile";
			}
		}
		if ($docfilelist ne "") {
			$install_script .= "\n/usr/bin/install -c -p -m 644$docfilelist %i/share/doc/%n/";
		}
	}

	# generate commands to install profile.d scripts
	if ($self->has_param("RuntimeVars")) {
	
		my ($var, $value, $vars, $properties);

		$vars = $self->param("RuntimeVars");
		# get rid of any indention first
		$vars =~ s/^\s+//gm;
		# Read the set if variavkes (but don't change the keys to lowercase)
		$properties = &read_properties_var('runtimevars of "'.$self->{_filename}.'"', $vars, 1);

		if(scalar keys %$properties > 0){
			$install_script .= "\n/usr/bin/install -d -m 755 %i/etc/profile.d";
			while (($var, $value) = each %$properties) {
				$install_script .= "\necho \"setenv $var '$value'\" >> %i/etc/profile.d/%n.csh.env";
				$install_script .= "\necho \"export $var='$value'\" >> %i/etc/profile.d/%n.sh.env";
			}
			# make sure the scripts exist
			$install_script .= "\n/usr/bin/touch %i/etc/profile.d/%n.csh";
			$install_script .= "\n/usr/bin/touch %i/etc/profile.d/%n.sh";
			# prepend *.env to *.[c]sh
			$install_script .= "\n/bin/cat %i/etc/profile.d/%n.csh >> %i/etc/profile.d/%n.csh.env";
			$install_script .= "\n/bin/cat %i/etc/profile.d/%n.sh >> %i/etc/profile.d/%n.sh.env";
			$install_script .= "\n/bin/mv -f %i/etc/profile.d/%n.csh.env %i/etc/profile.d/%n.csh";
			$install_script .= "\n/bin/mv -f %i/etc/profile.d/%n.sh.env %i/etc/profile.d/%n.sh";
			# make them executable (to allow them to be sourced by /sw/bin.init.[c]sh)
			$install_script .= "\n/bin/chmod 755 %i/etc/profile.d/%n.*";
		}
	}

	# generate commands to install App bundles
	if ($self->has_param("AppBundles")) {
		$install_script .= "\n/usr/bin/install -d -m 755 %i/Applications";
		for my $bundle (split(/\s+/, $self->param("AppBundles"))) {
			$bundle =~ s/\'/\\\'/gsi;
			$install_script .= "\ncp -pR '$bundle' '%i/Applications/'";
		}
		$install_script .= "\nchmod -R o-w '%i/Applications/'" .
			"\nif test -x /Developer/Tools/SplitForks; then" .
			"\n     /Developer/Tools/SplitForks '%i/Applications/'" .
			"\nfi";
	}

	# generate commands to install jar files
	if ($self->has_param("JarFiles")) {
		my (@jarfiles, $jarfile, $jarfilelist);
		# install jarfiles
		$install_script .= "\n/usr/bin/install -d -m 755 %i/share/java/%n";
		@jarfiles = split(/\s+/, $self->param("JarFiles"));
		$jarfilelist = "";
		foreach $jarfile (@jarfiles) {
			if ($jarfile =~ /^(.+)\:(.+)$/) {
				$install_script .= "\n/usr/bin/install -c -p -m 644 $1 %i/share/java/%n/$2";
			} else {
				$jarfilelist .= " $jarfile";
			}
		}
		if ($jarfilelist ne "") {
			$install_script .= "\n/usr/bin/install -c -p -m 644$jarfilelist %i/share/java/%n/";
		}
	}

	$install_script .= "\n/bin/rm -f %i/info/dir %i/info/dir.old %i/share/info/dir %i/share/info/dir.old";

	### install

	$self->run_script($install_script, "installing", 0);

	### splitoffs
	
	my $splitoff;
	foreach	 $splitoff (@{$self->{_splitoffs}}) {
		# iterate over all splitoffs and call their build phase
		$splitoff->phase_install(1);
	}

	### remove build dir

	if (not $do_splitoff) {
		$bdir = $self->get_fullname();
		chdir "$buildpath";
		if (not $config->param_boolean("KeepBuildDir") and not Fink::Config::get_option("keep_build") and -e $bdir) {
			rm_rf $bdir or
				&print_breaking("WARNING: Can't remove build directory $bdir. ".
								"This is not fatal, but you may want to remove ".
								"the directory manually to save disk space. ".
								"Continuing with normal procedure.");
		}
	}
}

### build .deb

sub phase_build {
	my $self = shift;
	my $do_splitoff = shift || 0;
	my ($ddir, $destdir, $control);
	my ($scriptname, $scriptfile, $scriptbody);
	my ($shlibsfile, $shlibsbody);
	my ($conffiles, $listfile, $infodoc);
	my ($daemonicname, $daemonicfile);
	my ($cmd);

	if ($self->is_type('dummy')) {
		die "build phase: can't build ".$self->get_fullname().
			" build".
				" because no package description is available\n";
	}
	if (exists $self->{parent} and not $do_splitoff) {
		($self->{parent})->phase_build();
		return;
	}

	chdir "$buildpath";
	$ddir = "root-".$self->get_fullname();
	$destdir = "$buildpath/$ddir";

	if (not -d "$destdir/DEBIAN") {
		mkdir_p "$destdir/DEBIAN" or
			die "can't create directory for control files for package ".$self->get_fullname()."\n";
	}

	# generate dpkg "control" file

	my ($pkgname, $parentpkgname, $version, $field, $section, $instsize);
	$parentpkgname = $pkgname = $self->get_name();
	$parentpkgname = $self->{parent}->get_name() if exists $self->{parent};
	$version = $self->get_fullversion();
	$section = $self->get_section();
	$instsize = $self->get_instsize("$destdir$basepath");	# kilobytes!
	$control = <<EOF;
Package: $pkgname
Source: $parentpkgname
Version: $version
Section: $section
Installed-Size: $instsize
Architecture: $debarch
EOF
	if ($self->param_boolean("BuildDependsOnly")) {
		$control .= "BuildDependsOnly: True\n";
	} elsif (defined $self->param_boolean("BuildDependsOnly")) {
		$control .= "BuildDependsOnly: False\n";
	} else {
		$control .= "BuildDependsOnly: Undefined\n";
	}
	if ($self->param_boolean("Essential")) {
		$control .= "Essential: yes\n";
	}

	eval {
		require File::Find;
		import File::Find;
	};

# Add a dependency on the darwin version (if not already present).
#   We depend on the major version only, in order to prevent users from
#   installing a .deb file created with an incorrect MACOSX_DEPLOYMENT_TARGET
#   value.
# FIXME: Actually, if the package states a darwin version we should combine
#   the version given by the package with the one we want to impose.
#   Instead, right now, we just use the package's version but this means
#   that a package will need to be revised if the darwin major version changes.

	my ($dummy, $darwin_version, $darwin_major_version);
	($dummy,$dummy,$darwin_version) = uname();
	if ($darwin_version =~ /(\d+)/) {
		$darwin_major_version = $1;
	} else {
		die "No major version number for darwin!";
	}

	my $has_darwin_dep;
	my $struct = &pkglist2lol($self->get_binary_depends()); 
	foreach (@$struct) {
		foreach (@$_) {
			$has_darwin_dep = 1 if /^darwin(\Z|\s|\()/;
		}
	}
	push @$struct, ["darwin (>= $darwin_major_version-1)"] if not $has_darwin_dep;
	$control .= "Depends: " . &lol2pkglist($struct) . "\n";

	foreach $field (qw(Provides Replaces Conflicts Pre-Depends
										 Recommends Suggests Enhances)) {
		if ($self->has_pkglist($field)) {
			$control .= "$field: ".&collapse_space($self->pkglist($field))."\n";
		}
	}
	foreach $field (qw(Maintainer)) {
		if ($self->has_param($field)) {
			$control .= "$field: ".&collapse_space($self->param($field))."\n";
		}
	}
	$control .= "Description: ".$self->get_description();

	### write "control" file

	print "Writing control file...\n";

	open(CONTROL,">$destdir/DEBIAN/control") or die "can't write control file for ".$self->get_fullname().": $!\n";
	print CONTROL $control;
	close(CONTROL) or die "can't write control file for ".$self->get_fullname().": $!\n";

	### update Mach-O Object List
	###
	### (but not for distributions prior to 10.2-gcc3.3)

	my $skip_prebinding = 0;
	my $pkgref = ($self);
	$skip_prebinding++ unless ($config->param("Distribution") ge "10.2-gcc3.3");
	$skip_prebinding++ if ($config->param("Distribution") ge "10.4");

	# Why do this?  On the off-chance the parent relationship is recursive (ie, a splitoff
	# depends on a splitoff, instead of the top-level package in the splitoff)
	# we work our way back to the top level, and skip prebinding if things are set
	# anywhere along the way (since the LD_* variables are normally set in the top-level
	# but need to take effect in, say, -shlibs)

	while (exists $pkgref->{_parent}) {
		$skip_prebinding++ if ($pkgref->param_boolean("NoSetLD_PREBIND"));
		$pkgref = $pkgref->{_parent};
	}
	$skip_prebinding++ if ($pkgref->param_boolean("NoSetLD_PREBIND"));

	# "our" instead of "my", so that it can be referenced later in the post-install script
	our %prebound_files = ();
	unless ($skip_prebinding) {

		print "Finding prebound objects...\n";
		my ($is_prebound, $is_exe, $name);
		find({ wanted => sub {
			# common things that shouldn't be objects
			return if (/\.(bz2|c|cfg|conf|class|cpp|csh|db|dll|gif|gz|h|html|info|ini|jpg|m4|mng|pdf|pl|png|po|py|sh|tar|tcl|txt|wav|xml)$/i);
			return unless (defined $_ and $_ ne "" and -f $_ and not -l $_);
			return if (readlink $_ =~ /\/usr\/lib/); # don't re-prebind stuff in /usr/lib
			#print "\$_ = $_\n";
			$is_prebound = 0;
			$is_exe      = 0;
			$name        = undef;
			my @dep_list;
			if (open(OTOOL, "otool -hLv '$_' |")) {
				while (<OTOOL>) {
					if (/^\s*MH_MAGIC.*EXECUTE.*PREBOUND.*$/) {
						# executable has no install_name, add to the list
						$name = $File::Find::name;
						my $destmeta = quotemeta($destdir);
						$name =~ s/^$destmeta//;
						$is_exe = 1;
						$is_prebound = 1;
					} elsif (/^\s*MH_MAGIC.*EXECUTE.*$/) {
						# if the last didn't match, but this did, it's a
						# non-prebound executable, so skip it
						last;
					} elsif (/^\s*MH_MAGIC.*PREBOUND.*$/) {
						# otherwise it's a dylib of some form, mark it
						# so we can pull the install_name in a few lines
						$is_prebound = 1;
					} elsif (/^\s*MH_MAGIC.*$/) {
						# if it wasn't an executable, and the last didn't
						# match, then it's not a prebound lib
						last;
					} elsif (my ($lib) = $_ =~ /^\s*(.+?) \(compatibility.*$/ and $is_prebound) {
						# we hit the install_name, add it to the list
						unless ($lib =~ /\/libSystem/ or $lib =~ /^\/+[Ss]ystem/ or $lib =~ /^\/usr\/lib/) {
							push(@dep_list, $lib);
						}
					}
				}
				close(OTOOL);
				if ($is_exe) {
					$prebound_files{$name} = \@dep_list;
				} else {
					$name = shift(@dep_list);
					return if (not defined $name);
					$prebound_files{$name} = \@dep_list;
				}
			}
		} }, $destdir);

		if (keys %prebound_files) {
			mkdir_p "$destdir$basepath/var/lib/fink/prebound/files" or
				die "can't make $destdir$basepath/var/lib/fink/prebound/files for ".$self->get_name().": $!\n";
			open(PREBOUND, '>' . $destdir . $basepath . '/var/lib/fink/prebound/files/' . $self->get_name() . '.pblist') or
				die "can't write " . $self->get_name() . '.pblist';
			print PREBOUND join("\n", sort keys %prebound_files), "\n";
			close(PREBOUND);
		}

		print "Writing dependencies...\n";
		for my $key (sort keys %prebound_files) {
			for my $file (@{$prebound_files{$key}}) {
				$file =~ s/\//-/g;
				$file =~ s/^-+//;
				mkdir_p "$destdir$basepath/var/lib/fink/prebound/deps/$file" or
					die "can't make $destdir$basepath/var/lib/fink/prebound/deps/$file for ".$self->get_name().": $!\n";
				open(DEPS, '>>' . $destdir . $basepath . '/var/lib/fink/prebound/deps/' . $file . '/' . $self->get_name() . '.deplist') or
					die "can't write " . $self->get_name() . '.deplist';
				print DEPS $key, "\n";
				close(DEPS);
			}
		}
	} # unless ($skip_prebinding)

	### create scripts as neccessary

	foreach $scriptname (qw(preinst postinst prerm postrm)) {
		# get script piece from package description
		if ($self->has_param($scriptname."Script")) {
			$scriptbody = $self->param($scriptname."Script");
		} else {
			$scriptbody = "";
		}

		# add UpdatePOD Code
		if ($self->param_boolean("UpdatePOD")) {
			# grab perl version, if present
			my ($perldirectory, $perlarchdir) = $self->get_perl_dir_arch();

			if ($scriptname eq "postinst") {
				$scriptbody .=
					"\n\n# Updating \%p/lib/perl5/$perlarchdir$perldirectory/perllocal.pod\n".
					"/bin/mkdir -p \%p/lib/perl5$perldirectory/$perlarchdir\n".
					"/bin/cat \%p/share/podfiles$perldirectory/*.pod > \%p/lib/perl5$perldirectory/$perlarchdir/perllocal.pod\n";
			} elsif ($scriptname eq "postrm") {
				$scriptbody .=
					"\n\n# Updating \%p/lib/perl5$perldirectory/$perlarchdir/perllocal.pod\n\n".
					"###\n".
					"### check to see if any .pod files exist in \%p/share/podfiles.\n".
					"###\n\n".
					"perl <<'END_PERL'\n\n".
					"if (-e \"\%p/share/podfiles$perldirectory\") {\n".
					"	 \@files = <\%p/share/podfiles$perldirectory/*.pod>;\n".
					"	 if (\$#files >= 0) {\n".
					"		 exec \"/bin/cat \%p/share/podfiles$perldirectory/*.pod > \%p/lib/perl5$perldirectory/$perlarchdir/perllocal.pod\";\n".
					"	 }\n".
					"}\n\n".
					"END_PERL\n";
			} 
		}

		# add JarFiles Code
		if ($self->has_param("JarFiles")) {
			if (($scriptname eq "postinst") || ($scriptname eq "postrm")) {
				$scriptbody.=
						"\n/bin/mkdir -p %p/share/java".
						"\njars=`/usr/bin/find %p/share/java -name '*.jar'`".
						"\n".'if (test -n "$jars")'.
						"\nthen".
						"\n".'(for jar in $jars ; do echo -n "$jar:" ; done) | sed "s/:$//" > %p/share/java/classpath'.
						"\nelse".
						"\n/bin/rm -f %p/share/java/classpath".
						"\nfi".
						"\nunset jars";
			}
		}

		# add Fink symlink Code
		if ($self->has_param("AppBundles")) {
			if ($scriptname eq "postinst") {
				$scriptbody .=
					"\nif \! test -e /Applications/Fink; then".
					"\n  /usr/bin/install -d -m 755 /Applications/Fink";

				for my $bundle (split(/\s+/, $self->param("AppBundles"))) {
					$bundle =~ s/\'/\\\'/gsi;
					my $shortname = basename($bundle);
					$scriptbody .= "\nln -s '%p/Applications/${shortname}' /Applications/Fink/";
				}

				$scriptbody .= "\nfi";
			}
		}

		# add auto-generated parts
		if ($self->has_param("InfoDocs")) {
			if ($scriptname eq "postinst") {
				$scriptbody .= "\n\n# generated from InfoDocs directive\n";
				$scriptbody .= "if [ -f %p/share/info/dir ]; then\n";
				foreach $infodoc (split(/\s+/, $self->param("InfoDocs"))) {
					next unless $infodoc;
					$infodoc = " \%p/share/info/$infodoc" unless $infodoc =~ /\//;
					$scriptbody .= "if [ -f %p/sbin/install-info ]; then\n";
					$scriptbody .= "	%p/sbin/install-info --infodir=\%p/share/info $infodoc\n";
					$scriptbody .= " elif [ -f %p/bootstrap/sbin/install-info ]; then\n";
					$scriptbody .= "	%p/bootstrap/sbin/install-info --infodir=\%p/share/info $infodoc\n";
					$scriptbody .= " fi\n";
								}
				$scriptbody .= "fi\n";
			} elsif ($scriptname eq "prerm") {
				$scriptbody .= "\n\n# generated from InfoDocs directive\n";
				$scriptbody .= "if [ -f %p/share/info/dir ]; then\n";
				foreach $infodoc (split(/\s+/, $self->param("InfoDocs"))) {
					next unless $infodoc;
					$scriptbody .= "	%p/sbin/install-info --infodir=\%p/share/info --remove $infodoc\n";
				}
				$scriptbody .= "fi\n";
			}
		}

		# add the call to redo prebinding on any packages with prebound files
		if (keys %prebound_files > 0 and $scriptname eq "postinst") {
			my $name = $self->get_name();
			$scriptbody .= <<EOF;

if test -x "$basepath/var/lib/fink/prebound/queue-prebinding.pl"; then
	$basepath/var/lib/fink/prebound/queue-prebinding.pl $name
fi

EOF
		}

		# do we have a non-empty script?
		next if $scriptbody eq "";

		# no, so write it out
		$scriptbody = &expand_percent($scriptbody, $self->{_expand}, $self->get_info_filename." \"$scriptname\"");
		$scriptfile = "$destdir/DEBIAN/$scriptname";

		print "Writing package script $scriptname...\n";

		open(SCRIPT,">$scriptfile") or die "can't write $scriptname script for ".$self->get_fullname().": $!\n";
		print SCRIPT <<EOF;
#!/bin/sh
# $scriptname script for package $pkgname, auto-created by fink

set -e

$scriptbody

exit 0
EOF
		close(SCRIPT) or die "can't write $scriptname script for ".$self->get_fullname().": $!\n";
		chmod 0755, $scriptfile;
	}

	### shlibs file

	if ($self->has_param("Shlibs")) {
			$shlibsbody = $self->param_expanded("Shlibs");
			chomp $shlibsbody;
			$shlibsfile = "$destdir/DEBIAN/shlibs";

			print "Writing shlibs file...\n";

# FIXME-dmacks:
#    * Make sure each file is actually present in $destdir
#    * Remove file if package isn't listed as a provider
#      (needed since only some variants may provide but we don't
#      have any condiitonal syntax in Shlibs)
#    * Rejoin wrap continuation lines
#      (use \ not heredoc multiline-field)

			open(SHLIBS,">$shlibsfile") or die "can't write shlibs file for ".$self->get_fullname().": $!\n";
			print SHLIBS <<EOF;
$shlibsbody
EOF
close(SHLIBS) or die "can't write shlibs file for ".$self->get_fullname().": $!\n";
			chmod 0644, $shlibsfile;
	}

	### config file list

	if ($self->has_param("conffiles")) {
		$listfile = "$destdir/DEBIAN/conffiles";
		$conffiles = join("\n", grep {$_} split(/\s+/, $self->param("conffiles")));
		$conffiles = &expand_percent($conffiles, $self->{_expand}, $self->get_info_filename." \"conffiles\"")."\n";

		print "Writing conffiles list...\n";

		open(SCRIPT,">$listfile") or die "can't write conffiles list file for ".$self->get_fullname().": $!\n";
		print SCRIPT $conffiles;
		close(SCRIPT) or die "can't write conffiles list file for ".$self->get_fullname().": $!\n";
		chmod 0644, $listfile;
	}

	### daemonic service file

	if ($self->has_param("DaemonicFile")) {
		$daemonicname = $self->param_default("DaemonicName", $self->get_name());
		$daemonicname .= ".xml";
		$daemonicfile = "$destdir$basepath/etc/daemons/".$daemonicname;

		print "Writing daemonic info file $daemonicname...\n";

		mkdir_p "$destdir$basepath/etc/daemons" or
			die "can't write daemonic info file for ".$self->get_fullname()."\n";
		open(SCRIPT,">$daemonicfile") or die "can't write daemonic info file for ".$self->get_fullname().": $!\n";
		print SCRIPT $self->param_expanded("DaemonicFile"), "\n";
		close(SCRIPT) or die "can't write daemonic info file for ".$self->get_fullname().": $!\n";
		chmod 0644, $daemonicfile;
	}

	### create .deb using dpkg-deb

	if (not -d $self->get_debpath()) {
		mkdir_p $self->get_debpath() or
			die "can't create directory for packages\n";
	}
	$cmd = "dpkg-deb -b $ddir ".$self->get_debpath();
	if (&execute($cmd)) {
		die "can't create package ".$self->get_debname()."\n";
	}

	symlink_f $self->get_debpath()."/".$self->get_debname(), "$basepath/fink/debs/".$self->get_debname() or
		die "can't symlink package ".$self->get_debname()." into pool directory\n";

	### splitoffs
	
	my $splitoff;
	foreach	 $splitoff (@{$self->{_splitoffs}}) {
		# iterate over all splitoffs and call their build phase
		$splitoff->phase_build(1);
	}

	### remove root dir

	if (not $config->param_boolean("KeepRootDir") and not Fink::Config::get_option("keep_root") and -e $destdir) {
		rm_rf $destdir or
			&print_breaking("WARNING: Can't remove package root directory ".
							"$destdir. ".
							"This is not fatal, but you may want to remove ".
							"the directory manually to save disk space. ".
							"Continuing with normal procedure.");
	}
}

### activate

sub phase_activate {
	my @packages = @_;
	my (@installable);

	for my $package (@packages) {
		my $deb = $package->find_debfile();

		unless (defined $deb and -f $deb) {
			die "can't find package ".$package->get_debname()."\n";
		}

		push(@installable, $package);
	}

	if (@installable == 0) {
		die "no installable .deb files found!\n";
	}

	my @deb_installable = map { $_->find_debfile() } @installable;
	if (&execute("dpkg -i @deb_installable")) {
		if (@installable == 1) {
			growl('finkPackageInstallationFailed', 'Fink installation failed.', "can't install package ".$installable[0]->get_fullname());
			die "can't install package ".$installable[0]->get_fullname()."\n";
		} else {
			growl('finkPackageInstallationFailed', 'Fink installation of ' . int(@installable) . ' packages failed.',
				"can't batch-install packages: @deb_installable");
			die "can't batch-install packages: @deb_installable\n";
		}
	} else {
		if (@installable == 1) {
			growl('finkPackageInstallationPassed', 'Fink installation passed.', "installed " . $installable[0]->get_fullname());
		} else {
			growl('finkPackageInstallationPassed', 'Fink installation of ' . int(@installable) . ' packages passed.', "batch-installed packages: @deb_installable");
		}
	}

	Fink::Status->invalidate();
}

### deactivate

sub phase_deactivate {
	my @packages = @_;

	if (&execute("dpkg --remove @packages")) {
		&print_breaking("ERROR: Can't remove package(s). Try 'fink remove --recursive " .
		                "@packages', which will also remove packages that depend " .
		                "on the package(s) to be removed.");
		if (@packages == 1) {
			growl('finkPackageRemovalFailed', 'Fink removal failed.', "can't remove package ".$packages[0]);
			die "can't remove package ".$packages[0]."\n";
		} else {
			growl('finkPackageRemovalFailed', 'Fink removal of ' . int(@packages) . ' packages failed.',
				"can't batch-remove packages: @packages");
			die "can't batch-remove packages: @packages\n";
		}
	} else {
		if (@packages == 1) {
			growl('finkPackageRemovalPassed', 'Fink removal passed.', "removed " . $packages[0]);
		} else {
			growl('finkPackageRemovalPassed', 'Fink removal of ' . int(@packages) . ' packages passed.',
				"batch-removed packages: @packages");
		}
	}

	Fink::Status->invalidate();
}

### deactivate recursive

sub phase_deactivate_recursive {
	my @packages = @_;

	if (&execute("apt-get remove @packages")) {
		if (@packages == 1) {
			die "can't remove package ".$packages[0]."\n";
		} else {
			die "can't batch-remove packages: @packages\n";
		}
	}
	Fink::Status->invalidate();
}

### purge

sub phase_purge {
	my @packages = @_;

	if (&execute("dpkg --purge @packages")) {
		&print_breaking("ERROR: Can't purge package(s). Try 'fink purge --recursive " .
		                "@packages', which will also purge packages that depend " .
		                "on the package to be purged.");
		if (@packages == 1) {
			die "can't purge package ".$packages[0]."\n";
		} else {
			die "can't batch-purge packages: @packages\n";
		}
	}
	Fink::Status->invalidate();
}

### purge recursive

sub phase_purge_recursive {
	my @packages = @_;

	if (&execute("apt-get remove --purge @packages")) {
		if (@packages == 1) {
			die "can't purge package ".$packages[0]."\n";
		} else {
			die "can't batch-purge packages: @packages\n";
		}
	}
	Fink::Status->invalidate();
}

# create an exclusive lock for the %f of the parent using dpkg
sub set_buildlock {
	my $self = shift;

	# bootstrapping occurs before we have package-management tools needed for buildlock
	return if $self->{_bootstrap};

	my $lockpkg_minor = 'fink-buildlock-' . $self->get_fullname();
	my $lockpkg = $lockpkg_minor . '-' .  strftime "%Y.%m.%d-%H.%M.%S", localtime;
	$self->{_lockpkg} = $lockpkg;

	my $destdir = "$buildpath/root-$lockpkg";

	if (not -d "$destdir/DEBIAN") {
		mkdir_p "$destdir/DEBIAN" or
			die "can't create directory for control files for package $lockpkg\n";
	}

	# generate dpkg "control" file

	my $control = <<EOF;
Package: $lockpkg
Source: fink
Version: 0-0
Section: unknown
Installed-Size: 0
Architecture: $debarch
Description: Package compile-time lockfile
Maintainer: Fink Core Group <fink-core\@lists.sourceforge.net>
Provides: fink-buildlock, $lockpkg_minor
EOF

	my @pkglist;

	# BuildConflicts of parent pkg are Conflicts of lockpkg
	if (exists $self->{parent}) {
		@pkglist = @{pkglist2lol($self->{parent}->pkglist('BuildConflicts'))};
	} else {
		@pkglist = @{pkglist2lol($self->pkglist('BuildConflicts'))};
	}
	push @pkglist, [$lockpkg_minor];  # prevent concurrent builds of the family
	$control .= 'Conflicts: ' . &lol2pkglist(\@pkglist) . "\n";

	# All *Depends of whole family of pkgs are Depends of lockpkg...
	@pkglist = ();
	foreach my $pkg ($self->get_splitoffs(1,1)) {
		push @pkglist, map { @{&pkglist2lol($pkg->pkglist($_))} } (qw(Depends Pre-Depends BuildDepends));
	}

	# ...but remove pkgs being built now (avoid chicken-and-egg)
	my $pkgregex = join "|", map { quotemeta($_->get_name()) } $self->get_splitoffs(1,1);
	$pkgregex = qr/^(?:$pkgregex)(?:\s*\(|\Z)/;  # a pkglist atom of any of us
	foreach my $deplist (@pkglist) {
		# nuke the whole OR cluster if any atom matches
		# ($deplist is the listref value from @depends so changing
		# $deplist changes the list linked from @depends; no need
		# to edit @depends directly)
		$deplist = [] if grep { /$pkgregex/ } @$deplist;
	}

	my $deplist = &lol2pkglist(\@pkglist);
	$control .= "Depends: $deplist\n" if length $deplist;

	### write "control" file
	open(CONTROL,">$destdir/DEBIAN/control") or die "can't write control file for $lockpkg: $!\n";
	print CONTROL $control;
	close(CONTROL) or die "can't write control file for $lockpkg: $!\n";

	### create .deb using dpkg-deb (in buildpath so apt doesn't see it)
	if (&execute("dpkg-deb -b $destdir $buildpath")) {
		die "can't create package $lockpkg\n";
	}
	rm_rf $destdir or
		&print_breaking("WARNING: Can't remove package root directory ".
						"$destdir. ".
						"This is not fatal, but you may want to remove ".
						"the directory manually to save disk space. ".
						"Continuing with normal procedure.");

	# install lockpkg (== set lockfile for building ourself)
	print "Setting build lock...\n";
	my $debfile = $buildpath.'/'.$lockpkg.'_0-0_'.$debarch.'.deb';
	my $lock_failed = &execute("dpkg -i $debfile");
	rm_f $debfile or
		&print_breaking("WARNING: Can't remove binary package file ".
						"$debfile. ".
						"This is not fatal, but you may want to remove ".
						"the file manually to save disk space. ".
						"Continuing with normal procedure.");
	if ($lock_failed) {
		print "Trying to clean up...\n";
		&execute("dpkg -r $lockpkg");
		my $fullname = $self->get_fullname();
		die <<EOMSG
Can't set build lock for $fullname.

There are two common causes for this, depending on the error message
following "Setting build lock..." above:

1. Problems with dependencies: fink has probably gotten confused by
   trying to build many packages at once. Try building just this
   current package. When that has completed successfully, retry
   whatever you did that led to the present error.

2. Conflicts among several fink-buildlock packages: fink thinks that
   the package it is about to build is currently being built by
   another fink process. If that is not true (perhaps a previous build
   attempt crashed?), just use fink to remove the currently-installed
   $lockpkg_minor- package(s).
   Then retry whatever you did that led to the present error.

In either case, don't worry, you have not wasted compiling time:
Packages that had been completely built before this error occurred
will not have to be recompiled.
EOMSG
	}

	# save ref to ourself in global config so can remove lock if build dies
	Fink::Config::set_options( { "Buildlock_PkgVersion" => $self } );
}

# remove the lock created by set_buildlock
# okay to call as a package method (will pull PkgVersion object from Config)
# or as object method (will use its own PkgVersion object)
sub clear_buildlock {
	my $self = shift;

	if (!ref $self) {
		# called as package method...look up PkgVersion object that locked
		$self = Fink::Config::get_option("Buildlock_PkgVersion");
		return if !ref $self;   # get out if there's no lock recorded
	}

	# bootstrapping occurs before we have package-management tools needed for buildlock
	return if $self->{_bootstrap};

	my $lockpkg = $self->{_lockpkg};

	# remove $lockpkg (== clear lock for building $self)
	print "Removing build lock...\n";
	if (&execute("dpkg -r $lockpkg")) {
		&print_breaking("WARNING: Can't remove package ".
						"$lockpkg. ".
						"This is not fatal, but you may want to remove ".
						"the package manually as it may interfere with ".
						"further fink operations. ".
						"Continuing with normal procedure.");
	}

	# we're gone
	Fink::Config::set_options( { "Buildlock_PkgVersion" => undef } );
}

# returns hashref for the ENV to be used while running package scripts
# does not alter global ENV

sub get_env {
	my $self = shift;
	my ($varname, $expand, $ccache_dir);
	my %script_env;

	# just return cached copy if there is one
	if (exists $self->{_script_env} and not $self->{_bootstrap}) {
		# return ref to a copy, so caller changes do not modify cached value
		return \%{$self->{_script_env}};
	}

	# bits of ENV that can be altered by SetENVVAR and NoSetENVVAR in a .info
	# Remember to update Packaging Manual if you change this var list!
	our @setable_env_vars = (
		"CC", "CFLAGS",
		"CPP", "CPPFLAGS",
		"CXX", "CXXFLAGS",
		"DYLD_LIBRARY_PATH",
		"JAVA_HOME",
		"LD_PREBIND",
		"LD_PREBIND_ALLOW_OVERLAP",
		"LD_FORCE_NO_PREBIND",
		"LD_SEG_ADDR_TABLE",
		"LD", "LDFLAGS", 
		"LIBRARY_PATH", "LIBS",
		"MACOSX_DEPLOYMENT_TARGET",
		"MAKE", "MFLAGS", "MAKEFLAGS",
	);

	# default environment variable values
	# Remember to update FAQ 8.3 if you change this var list!
	my %defaults = (
		"CPPFLAGS"                 => "-I\%p/include",
		"LDFLAGS"                  => "-L\%p/lib",
		"LD_PREBIND"               => 1,
		"LD_PREBIND_ALLOW_OVERLAP" => 1,
		"LD_SEG_ADDR_TABLE"        => "$basepath/var/lib/fink/prebound/seg_addr_table",
	);

	# lay the groundwork for prebinding
	if (! -f "$basepath/var/lib/fink/prebound/seg_addr_table") {
		mkdir_p "$basepath/var/lib/fink/prebound" or
			warn "couldn't create seg_addr_table directory, this may cause compilation to fail!\n";
		if (open(FILEOUT, ">$basepath/var/lib/fink/prebound/seg_addr_table")) {
			print FILEOUT <<END;
0x90000000  0xa0000000  <<< Next split address to assign >>>
0x20000000  <<< Next flat address to assign >>>
END
			close(FILEOUT);
		} else {
			warn "couldn't create seg_addr_table, this may cause compilation to fail!\n";
		}
	}

	# start with a clean the environment
	# uncomment this to be able to use distcc -- not officially supported!
	#$defaults{'MAKEFLAGS'} = $ENV{'MAKEFLAGS'} if (exists $ENV{'MAKEFLAGS'});
	%script_env = ("HOME" => $ENV{"HOME"});

	# add system path
	$script_env{"PATH"} = "/bin:/usr/bin:/sbin:/usr/sbin";
	
	# add bootstrap path if necessary
	my $bsbase = Fink::Bootstrap::get_bsbase();
	if (-d $bsbase) {
		$script_env{"PATH"} = "$bsbase/bin:$bsbase/sbin:" . $script_env{"PATH"};
	}
	
	# Stop ccache stompage: allow user to specify directory via fink.conf
	$ccache_dir = $config->param_default("CCacheDir", "$basepath/var/ccache");
	unless ( lc $ccache_dir eq "none" ) {
		# make sure directory exists
		if ( not -d $ccache_dir and not mkdir_p($ccache_dir) ) {
			die "WARNING: Something is preventing the creation of " .
				"\"$ccache_dir\" for CCacheDir, so CCACHE_DIR will not ".
				"be set.\n";
		} else {
			$script_env{CCACHE_DIR} = $ccache_dir;
		}
	}

	# get full environment: parse what a shell has after sourcing init.sh
	# script when starting with the (purified) ENV we have so far
	if (-r "$basepath/bin/init.sh") {
		my %temp_ENV = %ENV;  # need to activatescript_env, so save ENV for later
		%ENV = %script_env;
		my @vars = `sh -c ". $basepath/bin/init.sh ; /usr/bin/env"`;
		%ENV = %temp_ENV;     # restore previous ENV
		chomp @vars;
		%script_env = map { split /=/,$_,2 } @vars;
		delete $script_env{_};  # artifact of how we fetch init.sh results
	}

	# set variables according to the info file
	$expand = $self->{_expand};
	foreach $varname (@setable_env_vars) {
		my $s;
		# start with fink's default unless .info says not to
		$s = $defaults{$varname} unless $self->param_boolean("NoSet$varname");
		if ($self->has_param("Set$varname")) {
			# set package-defined value (prepend if still have a default)
			if (defined $s) {
				$s = $self->param("Set$varname") . " $s";
			} else {
				$s = $self->param("Set$varname");
			}
		}
		if (defined $s) {
			# %-expand and store if we have anything at all
			$script_env{$varname} = &expand_percent($s, $expand, $self->get_info_filename." \"set$varname\" or \%Fink::PkgVersion::get_env::defaults");
		} else {
			# otherwise do not set
			delete $script_env{$varname};
		}
	}

	# handle MACOSX_DEPLOYMENT_TARGET
	my $sw_vers = Fink::Services::get_sw_vers();
	if (not $self->has_param("SetMACOSX_DEPLOYMENT_TARGET") and defined $sw_vers and $sw_vers ne "0") {
		$sw_vers =~ s/^(\d+\.\d+).*$/$1/;
		if ($sw_vers eq "10.2") {
			$script_env{'MACOSX_DEPLOYMENT_TARGET'} = '10.1';
		} else {
			$script_env{'MACOSX_DEPLOYMENT_TARGET'} = $sw_vers;
		}
	}

	# special things for Type:java
	if (not $self->has_param('SetJAVA_HOME') or not $self->has_param('SetPATH')) {
		if ($self->is_type('java')) {
			my ($JAVA_HOME, $subtype, $dir, $versions_dir, @dirs);
			if ($subtype = $self->get_subtype('java')) {
				$subtype = '' if ($subtype eq 'java');
				$versions_dir = '/System/Library/Frameworks/JavaVM.framework/Versions';
				if (opendir(DIR, $versions_dir)) {
					@dirs = sort(grep(/^${subtype}/, readdir(DIR)));
					@dirs = reverse(@dirs) if ($subtype eq "");
					for $dir (@dirs) {
						if ($dir =~ /^${subtype}/ and -f "$versions_dir/$dir/Headers/jni.h") {
							$JAVA_HOME = "$versions_dir/$dir/Home";
						}
					}
					closedir(DIR);
				}
			}
			$script_env{'JAVA_HOME'} = $JAVA_HOME unless $self->has_param('SetJAVA_HOME');
			$script_env{'PATH'}      = $JAVA_HOME . '/bin:' . $script_env{'PATH'} unless $self->has_param('SetPATH');
		}
	}

	# cache a copy so caller's changes to returned val don't touch cached val
	if (not $self->{_bootstrap}) {
		$self->{_script_env} = { %script_env };
	}

	return \%script_env;
}

### run script

sub run_script {
	my $self = shift;
	my $script = shift;
	my $phase = shift;
	my $no_expand = shift || 0;
	my ($script_env, %env_bak);


	# Expand percent shortcuts
	$script = &expand_percent($script, $self->{_expand}, $self->get_info_filename." $phase script") unless $no_expand;

	# Run the script
	$script_env = $self->get_env();# fetch script environment
	%env_bak = %ENV;        # backup existing environment
	%ENV = %$script_env;    # run under modified environment
	if (&execute_script($script)) {
		die $phase." ".$self->get_fullname()." failed\n";
	}
	%ENV = %env_bak;        # restore previous environment
}



### get_perl_dir_arch

sub get_perl_dir_arch {
	my $self = shift;

	# grab perl version, if present
	my $perlversion   = "";
#get_system_perl_version();
	my $perldirectory = "";
	my $perlarchdir;
	if ($self->is_type('perl') and $self->get_subtype('perl') ne 'perl') {
		$perlversion = $self->get_subtype('perl');
		$perldirectory = "/" . $perlversion;
	}
	### PERL= needs a full path or you end up with
	### perlmods trying to run ../perl$perlversion
	my $perlcmd = get_path('perl'.$perlversion);

	if ($perlversion ge "5.8.1") {
		$perlarchdir = 'darwin-thread-multi-2level';
	} else {
		$perlarchdir = 'darwin';
	}

	return ($perldirectory, $perlarchdir,$perlcmd);
}

### get_ruby_dir_arch

sub get_ruby_dir_arch {
	my $self = shift;

	# grab ruby version, if present
	my $rubyversion   = "";
	my $rubydirectory = "";
	my $rubyarchdir   = "powerpc-darwin";
	if ($self->is_type('ruby') and $self->get_subtype('ruby') ne 'ruby') {
		$rubyversion = $self->get_subtype('ruby');
		$rubydirectory = "/" . $rubyversion;
	}
	### ruby= needs a full path or you end up with
	### rubymods trying to run ../ruby$rubyversion
	my $rubycmd = get_path('ruby'.$rubyversion);

	return ($rubydirectory, $rubyarchdir, $rubycmd);
}

### EOF

1;
