#
# Fink::PkgVersion class
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

package Fink::PkgVersion;
use Fink::Base;

use Fink::Services qw(&filename &expand_percent &expand_url &execute
                      &latest_version &print_breaking
                      &print_breaking_twoprefix &prompt_boolean);
use Fink::Package;
use Fink::Config qw($config $basepath $libpath $debarch);

use strict;
use warnings;

BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  $VERSION = 1.00;
  @ISA         = qw(Exporter Fink::Base);
  @EXPORT      = qw();
  @EXPORT_OK   = qw();  # eg: qw($Var1 %Hashit &func3);
  %EXPORT_TAGS = ( );   # eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

END { }       # module clean-up code here (global destructor)


### self-initialization

sub initialize {
  my $self = shift;
  my ($pkgname, $version, $revision, $filename, $source);
  my ($depspec, $deplist, $dep, $expand, $configure_params, $destdir);
  my ($i, $path, @parts, $finkinfo_index, $section);

  $self->SUPER::initialize();

  $self->{_name} = $pkgname = $self->param_default("Package", "");
  $self->{_version} = $version = $self->param_default("Version", "0");
  $self->{_revision} = $revision = $self->param_default("Revision", "0");
  $self->{_type} = lc $self->param_default("Type", "");
  # the following is set by Fink::Package::scan
  $self->{_filename} = $filename = $self->{thefilename};

  # path handling
  @parts = split(/\//, $filename);
  pop @parts;   # remove filename
  $self->{_patchpath} = join("/", @parts);
  for ($finkinfo_index = $#parts;
       $finkinfo_index > 0 and $parts[$finkinfo_index] ne "finkinfo";
       $finkinfo_index--) {
    # this loop intentionally left blank
  }
  if ($finkinfo_index <= 0) {
    die "Path \"$filename\" contains no finkinfo directory!\n";
  }
  $section = $parts[$finkinfo_index-1]."/";
  if ($finkinfo_index < $#parts) {
    $section = "" if $section eq "main/";
    $section .= join("/", @parts[$finkinfo_index+1..$#parts])."/";
  }
  $self->{_section} = substr($section,0,-1);   # cut last /
  $parts[$finkinfo_index] = "binary-$debarch";
  $self->{_debpath} = join("/", @parts);
  $self->{_debpaths} = [];
  for ($i = $#parts; $i >= $finkinfo_index; $i--) {
    push @{$self->{_debpaths}}, join("/", @parts[0..$i]);
  }

  # some commonly used stuff
  $self->{_fullversion} = $version."-".$revision;
  $self->{_fullname} = $pkgname."-".$version."-".$revision;
  $self->{_debname} = $pkgname."_".$version."-".$revision."_".$debarch.".deb";

  # percent-expansions
  $configure_params = "--prefix=\%p ".
    $self->param_default("ConfigureParams", "");
  $destdir = "$basepath/src/root-".$self->{_fullname};
  $expand = { 'n' => $pkgname,
	      'v' => $version,
	      'r' => $revision,
	      'f' => $self->{_fullname},
	      'p' => $basepath, 'P' => $basepath,
	      'd' => $destdir,
	      'i' => $destdir.$basepath,
	      'a' => $self->{_patchpath},
	      'c' => $configure_params};
  $self->{_expand} = $expand;

  # parse dependencies
  $depspec = $self->param_default("Depends", "");
  $deplist = [ split(/\s*\,\s*/, $depspec) ];
  $self->{_depends} = $deplist;

  # expand source
  $source = $self->param_default("Source", "\%n-\%v.tar.gz");
  if ($source eq "gnu") {
    $source = "mirror:gnu:\%n/\%n-\%v.tar.gz";
  } elsif ($source eq "gnome") {
    $source = "mirror:gnome:stable/sources/\%n/\%n-\%v.tar.gz";
  }

  $source = &expand_percent($source, $expand);
  $self->{source} = $source;
  $self->{_sourcecount} = 1;

  for ($i = 2; $self->has_param('source'.$i); $i++) {
    $self->{'source'.$i} = &expand_percent($self->{'source'.$i}, $expand);
    $self->{_sourcecount} = $i;
  }

  $self->{_bootstrap} = 0;
}

### merge duplicate package description

sub merge {
  my $self = shift;
  my $dup = shift;

  push @{$self->{_debpaths}}, @{$dup->{_debpaths}};
}

### bootstrap helpers

sub enable_bootstrap {
  my $self = shift;
  my $bsbase = shift;

  $self->{_expand}->{p} = $bsbase;
  $self->{_expand}->{d} = "";
  $self->{_expand}->{i} = $bsbase;
  $self->{_bootstrap} = 1;
}

sub disable_bootstrap {
  my $self = shift;
  my ($destdir);

  $destdir = "$basepath/src/root-".$self->{_fullname};
  $self->{_expand}->{p} = $basepath;
  $self->{_expand}->{d} = $destdir;
  $self->{_expand}->{i} = $destdir.$basepath;
  $self->{_bootstrap} = 0;
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

### other accessors

sub is_multisource {
  my $self = shift;
  return $self->{_sourcecount} > 1;
}

sub get_source {
  my $self = shift;
  my $index = shift || 1;
  if ($index < 2) {
    return $self->param("Source");
  } elsif ($index <= $self->{_sourcecount}) {
    return $self->param("Source".$index);
  }
  return "-";
}

sub get_tarball {
  my $self = shift;
  my $index = shift || 1;
  if ($index < 2) {
    return &filename($self->param("Source"));
  } elsif ($index <= $self->{_sourcecount}) {
    return &filename($self->param("Source".$index));
  }
  return "-";
}

sub get_build_directory {
  my $self = shift;
  my ($dir);

  if (exists $self->{_builddir}) {
    return $self->{_builddir};
  }

  if ($self->param_boolean("NoSourceDirectory")) {
    $self->{_builddir} = $self->get_fullname();
    return $self->{_builddir};
  }
  if ($self->has_param("SourceDirectory")) {
    $self->{_builddir} = $self->get_fullname()."/".
      &expand_percent($self->param("SourceDirectory"), $self->{_expand});
    return $self->{_builddir};
  }

  $dir = $self->get_tarball();
  if ($dir =~ /^(.*)\.tar(\.(gz|z|Z|bz2))?$/) {
    $dir = $1;
  }
  if ($dir =~ /^(.*)\.(tgz|zip)$/) {
    $dir = $1;
  }

  $self->{_builddir} = $self->get_fullname()."/".$dir;
  return $self->{_builddir};
}

### generate description

sub format_description {
  my $s = shift;

  # remove last newline (if any)
  chomp $s;
  # replace empty lines with "."
  $s =~ s/^\s*$/\./mg;
  # add leading space
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

sub get_description {
  my $self = shift;
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

  if ($self->has_param("DescUsage")) {
    $desc .= " .\n Usage Notes:\n";
    $desc .= &format_description($self->param("DescUsage"));
  }

  if ($self->has_param("Homepage")) {
    $desc .= " .\n Web site: ".&format_oneline($self->param("Homepage"))."\n";
  }

  if ($self->has_param("DescPackaging")) {
    $desc .= " .\n Packaging Notes:\n";
    $desc .= &format_description($self->param("DescPackaging"));
  }

  if ($self->has_param("DescPort")) {
    $desc .= " .\n Porting Notes:\n";
    $desc .= &format_description($self->param("DescPort"));
  }

  return $desc;
}

### get installation state

sub is_fetched {
  my $self = shift;
  my ($i);

  if ($self->{_type} eq "bundle") {
    return 1;
  }

  for ($i = 1; $i <= $self->{_sourcecount}; $i++) {
    if (not defined $self->find_tarball($i)) {
      return 0;
    }
  }
  return 1;
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

  if (exists $self->{_installed}) {
    return $self->{_installed};
  }

  if (-e "$basepath/var/fink-stamp/".$self->get_fullname()) {
    $self->{_installed} = 1;
  } else {
    $self->{_installed} = 0;
  }
  return $self->{_installed};
}

### source tarball finding

sub find_tarball {
  my $self = shift;
  my $index = shift || 1;
  my ($archive, $found_archive);
  my (@search_dirs, $search_dir);

  $archive = $self->get_tarball($index);
  if ($archive eq "-") {  # bad index
    return undef;
  }

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
  return undef;
}

### get dependencies

sub get_depends {
  my $self = shift;

  return @{$self->{_depends}};
}

sub resolve_depends {
  my $self = shift;
  my ($depname, $package, @deplist);

  @deplist = ();
  foreach $depname (@{$self->{_depends}}) {
    $package = Fink::Package->package_by_name($depname);
    if (not defined $package) {
      die "Can't resolve dependency \"$depname\" for package \"".$self->get_fullname()."\"\n";
    }
    push @deplist, [ $package->get_all_providers() ];
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

  foreach $confname (split(/\s*\,\s*/,
			   $self->param_default("Conflicts", ""))) {
    $package = Fink::Package->package_by_name($confname);
    if (not defined $package) {
      die "Can't resolve anti-dependency \"$confname\" for package \"".$self->get_fullname()."\"\n";
    }
    push @conflist, [ $package->get_all_providers() ];
  }

  return @conflist;
}


### find package and version by matching a specification

sub match_package {
  shift;  # class method - ignore first parameter
  my $s = shift;
  my $quiet = shift || 0;

  my ($pkgname, $package, $version, $pkgversion);
  my ($found, @parts, $i, @vlist, $v, @rlist);


  if (not $config->param_boolean("Verbose")) {
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

  print "pkg $pkgname  version $version\n"
    unless $quiet;

  # we now have the package name in $pkgname, the package
  # object in $package, and the
  # still to be matched version (or "###") in $version.
  if ($version eq "###") {
    # find the newest version

    $version = &latest_version($package->list_versions());
    if (defined $version) {
      print "pkg $pkgname  version $version\n"
	unless $quiet;
    } else {
      # there's nothing we can do here...
      die "no version info available for $pkgname\n";
    }
  } elsif (not defined $package->get_version($version)) {
    # try to match the version

    @vlist = $package->list_versions();
    @rlist = ();
    foreach $v (@vlist)  {
      if ($package->get_version($v)->get_version() eq $version) {
	push @rlist, $v;
      }
    }
    $version = &latest_version(@rlist);
    if (defined $version) {
      print "pkg $pkgname  version $version\n"
	unless $quiet;
    } else {
      # there's nothing we can do here...
      die "no matching version found for $pkgname\n";
    }
  }

  return $package->get_version($version);
}

###
### PHASES
###

### fetch

sub phase_fetch {
  my $self = shift;
  my $conditional = shift || 0;
  my ($i);

  if ($self->{_type} eq "bundle") {
    return;
  }

  for ($i = 1; $i <= $self->{_sourcecount}; $i++) {
    if (not $conditional or not defined $self->find_tarball($i)) {
      $self->fetch_source($i);
    }
  }
}

sub fetch_source {
  my $self = shift;
  my $index = shift;
  my ($url, $file, $params);
  my ($http_proxy, $ftp_proxy);

  chdir "$basepath/src";

  $url = &expand_url($self->get_source($index));
  $file = $self->get_tarball($index);

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
    print "\n";
    &print_breaking("Downloading '$file' from the URL '$url' failed. ".
		    "There can be several reasons for this:");
    &print_breaking_twoprefix("The server is too busy to let you in or ".
			      "is temporarily down. Try again later.",
			      1, "- ", "  ");
    &print_breaking_twoprefix("There is a network problem. If you are ".
			      "behind a firewall you may want to check ".
			      "the proxy and passive mode FTP ".
			      "settings. Then try again.",
			      1, "- ", "  ");
    &print_breaking_twoprefix("The file was removed from the server or ".
			      "moved to another directory. The package ".
			      "description must be updated.",
			      1, "- ", "  ");
    &print_breaking("In any case, you can download '$file' manually and ".
		    "put it in '$basepath/src', then run fink again with ".
		    "the same command.");
    print "\n";

    die "file download failed for $file of package ".$self->get_fullname()."\n";
  }
}

### unpack

sub phase_unpack {
  my $self = shift;
  my ($archive, $found_archive, $bdir, $destdir, $unpack_cmd);
  my ($i, $verbosity);

  if ($self->{_type} eq "bundle") {
    return;
  }

  $bdir = $self->get_fullname();

  $verbosity = "";
  if ($config->param_boolean("Verbose")) {
    $verbosity = "v";
  }

  # remove dir if it exists
  chdir "$basepath/src";
  if (-e $bdir) {
    if (&execute("rm -rf $bdir")) {
      die "can't remove existing directory $bdir\n";
    }
  }

  for ($i = 1; $i <= $self->{_sourcecount}; $i++) {
    $archive = $self->get_tarball($i);

    # search for archive, try fetching if not found
    $found_archive = $self->find_tarball($i);
    if (not defined $found_archive) {
      $self->fetch_source($i);
      $found_archive = $self->find_tarball($i);
    }
    if (not defined $found_archive) {
      die "can't find source tarball $archive for package ".$self->get_fullname()."\n";
    }

    # determine unpacking command
    $unpack_cmd = "cp $found_archive .";
    if ($archive =~ /[\.\-]tar\.(gz|z|Z)$/ or $archive =~ /\.tgz$/) {
      $unpack_cmd = "gzip -dc $found_archive | tar -x${verbosity}f -";
    } elsif ($archive =~ /[\.\-]tar\.bz2$/) {
      $unpack_cmd = "bzip2 -dc $found_archive | tar -x${verbosity}f -";
    } elsif ($archive =~ /[\.\-]tar$/) {
      $unpack_cmd = "tar -x${verbosity}f $found_archive";
    } elsif ($archive =~ /\.zip$/) {
      $unpack_cmd = "unzip -o $found_archive";
    }

    # calculate destination directory
    $destdir = "$basepath/src/$bdir";
    if ($i > 1) {
      if ($self->has_param("Source".$i."ExtractDir")) {
	$destdir .= "/".&expand_percent($self->param("Source".$i."ExtractDir"), $self->{_expand});
      }
    }

    # create directory
    if (&execute("mkdir -p $destdir")) {
      die "can't create directory $destdir\n";
    }

    # unpack it
    chdir $destdir;
    if (&execute($unpack_cmd)) {
      die "unpacking ".$self->get_fullname()." failed\n";
    }
  }
}

### patch

sub phase_patch {
  my $self = shift;
  my ($dir, $patch_script, $cmd, $patch);

  if ($self->{_type} eq "bundle") {
    return;
  }

  $dir = $self->get_build_directory();
  if (not -d "$basepath/src/$dir") {
    die "directory $basepath/src/$dir doesn't exist, check the package description\n";
  }
  chdir "$basepath/src/$dir";

  $patch_script = "";

  ### copy host type scripts (config.guess and config.sub) if required

  if ($self->param_boolean("UpdateConfigGuess")) {
    $patch_script .=
      "cp -f $libpath/update/config.guess .\n".
      "cp -f $libpath/update/config.sub .\n";
  }

  ### copy libtool scripts (ltconfig and ltmain.sh) if required

  if ($self->param_boolean("UpdateLibtool")) {
    $patch_script .=
      "cp -f $libpath/update/ltconfig .\n".
      "cp -f $libpath/update/ltmain.sh .\n";
  }

  ### patches specifies by filename

  if ($self->has_param("Patch")) {
    foreach $patch (split(/\s+/,$self->param("Patch"))) {
      $patch_script .= "patch -p1 <\%a/$patch\n";
    }
  }

  ### any additional commands

  if ($self->has_param("PatchScript")) {
    $patch_script .= $self->param("PatchScript");
  }

  $patch_script = &expand_percent($patch_script, $self->{_expand});

  ### patch

  $self->set_env();
  foreach $cmd (split(/\n/,$patch_script)) {
    next unless $cmd;   # skip empty lines

    if (&execute($cmd)) {
      die "patching ".$self->get_fullname()." failed\n";
    }
  }
}

### compile

sub phase_compile {
  my $self = shift;
  my ($dir, $compile_script, $cmd);

  if ($self->{_type} eq "bundle") {
    return;
  }

  $dir = $self->get_build_directory();
  if (not -d "$basepath/src/$dir") {
    die "directory $basepath/src/$dir doesn't exist, check the package description\n";
  }
  chdir "$basepath/src/$dir";

  # generate compilation script
  $compile_script =
    "./configure \%c\n".
    "make";
  if ($self->has_param("CompileScript")) {
    $compile_script = $self->param("CompileScript");
  }

  $compile_script = &expand_percent($compile_script, $self->{_expand});

  ### compile

  $self->set_env();
  foreach $cmd (split(/\n/,$compile_script)) {
    next unless $cmd;   # skip empty lines

    if (&execute($cmd)) {
      die "compiling ".$self->get_fullname()." failed\n";
    }
  }
}

### install

sub phase_install {
  my $self = shift;
  my ($dir, $install_script, $cmd, $bdir);

  if ($self->{_type} ne "bundle") {
    $dir = $self->get_build_directory();
    if (not -d "$basepath/src/$dir") {
      die "directory $basepath/src/$dir doesn't exist, check the package description\n";
    }
    chdir "$basepath/src/$dir";
  }

  # generate installation script

  $install_script = "";
  unless ($self->{_bootstrap}) {
    $install_script .= "rm -rf \%d\n";
  }
  $install_script .= "mkdir -p \%i\n";
  unless ($self->{_bootstrap}) {
    $install_script .= "mkdir -p \%d/DEBIAN\n";
  }
  if ($self->{_type} ne "bundle") {
    if ($self->has_param("InstallScript")) {
      $install_script .= $self->param("InstallScript");
    } else {
      $install_script .= "make install prefix=\%i";
    }
  }
  $install_script .= "\nmkdir -p \%i/var/fink-stamp".
    "\ntouch \%i/var/fink-stamp/\%f".
    "\nrm -f %i/info/dir %i/info/dir.old %i/share/info/dir %i/share/info/dir.old";

  $install_script = &expand_percent($install_script, $self->{_expand});

  ### install

  $self->set_env();
  foreach $cmd (split(/\n/,$install_script)) {
    next unless $cmd;   # skip empty lines

    if (&execute($cmd)) {
      die "installing ".$self->get_fullname()." failed\n";
    }
  }

  ### remove build dir

  $bdir = $self->get_fullname();
  chdir "$basepath/src";
  if (not $config->param_boolean("KeepBuildDir") and -e $bdir) {
    if (&execute("rm -rf $bdir")) {
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
  my ($ddir, $destdir, $control);
  my ($scriptname, $scriptfile, $scriptbody);
  my ($conffiles, $listfile);
  my ($daemonicname, $daemonicfile);
  my ($cmd);

  chdir "$basepath/src";
  $ddir = "root-".$self->get_fullname();
  $destdir = "$basepath/src/$ddir";

  if (not -d "$destdir/DEBIAN") {
    if (&execute("mkdir -p $destdir/DEBIAN")) {
      die "can't create directory for control files for package ".$self->get_fullname()."\n";
    }
  }

  # generate dpkg "control" file

  my ($pkgname, $version, $field);
  $pkgname = $self->get_name();
  $version = $self->get_fullversion();
  $control = <<EOF;
Package: $pkgname
Source: $pkgname
Version: $version
Architecture: $debarch
EOF
  $control .= "Depends: ".join(", ", @{$self->{_depends}})."\n";
  if ($self->param_boolean("Essential")) {
    $control .= "Essential: yes\n";
  }
  foreach $field (qw(Maintainer Provides Replaces Conflicts)) {
    if ($self->has_param($field)) {
      $control .= "$field: ".$self->param($field)."\n";
    }
   }
  $control .= "Description: ".$self->get_description();

  ### write "control" file

  print "Writing control file...\n";

  open(CONTROL,">$destdir/DEBIAN/control") or die "can't write control file for ".$self->get_fullname().": $!\n";
  print CONTROL $control;
  close(CONTROL) or die "can't write control file for ".$self->get_fullname().": $!\n";

  ### create scripts as neccessary

  foreach $scriptname (qw(preinst postinst prerm postrm)) {
    next unless $self->has_param($scriptname."Script");

    $scriptbody = $self->param($scriptname."Script");
    $scriptbody = &expand_percent($scriptbody, $self->{_expand});
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

  ### config file list

  if ($self->has_param("conffiles")) {
    $listfile = "$destdir/DEBIAN/conffiles";
    $conffiles = join("\n", split(/\s+/, $self->param("conffiles")))."\n";
    $conffiles = &expand_percent($conffiles, $self->{_expand});

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

    if (&execute("mkdir -p $destdir$basepath/etc/daemons")) {
      die "can't write daemonic info file for ".$self->get_fullname()."\n";
    }
    open(SCRIPT,">$daemonicfile") or die "can't write daemonic info file for ".$self->get_fullname().": $!\n";
    print SCRIPT &expand_percent($self->param("DaemonicFile"), $self->{_expand});
    close(SCRIPT) or die "can't write daemonic info file for ".$self->get_fullname().": $!\n";
    chmod 0644, $daemonicfile;
  }

  ### create .deb using dpkg-deb

  if (not -d $self->get_debpath()) {
    if (&execute("mkdir -p ".$self->get_debpath())) {
      die "can't create directory for packages\n";
    }
  }
  $cmd = "dpkg-deb -b $ddir ".$self->get_debpath();
  if (&execute($cmd)) {
    die "can't create package ".$self->get_debname()."\n";
  }

  if (&execute("ln -sf ".$self->get_debpath()."/".$self->get_debname()." ".
	       "$basepath/fink/debs/")) {
    die "can't symlink package ".$self->get_debname()." into pool directory\n";
  }

  ### remove root dir

  if (not $config->param_boolean("KeepRootDir") and -e $destdir) {
    if (&execute("rm -rf $destdir")) {
      &print_breaking("WARNING: Can't remove package build directory ".
		      "$destdir. ".
		      "This is not fatal, but you may want to remove ".
		      "the directory manually to save disk space. ".
		      "Continuing with normal procedure.");
    }
  }
}

### activate

sub phase_activate {
  my $self = shift;
  my ($deb, $answer);

  $deb = $self->find_debfile();

  unless (defined $deb and -f $deb) {
    die "can't find package ".$self->get_debname()."\n";
  }

  while(1) {
    delete $self->{_installed};
    if (&execute("dpkg -i $deb")) {
      die "can't install package ".$self->get_fullname()."\n";
    }
    last if $self->is_installed();

    $answer =
      &prompt_boolean("WARNING: dpkg malfunction detected. Not all files ".
		      "were extracted. Retry installing?");
    last if not $answer;
  }
}

### deactivate

sub phase_deactivate {
  my $self = shift;

  delete $self->{_installed};

  if (&execute("dpkg --remove ".$self->get_name())) {
    die "can't remove package ".$self->get_fullname()."\n";
  }
}

### set environment variables according to spec

sub set_env {
  my $self = shift;
  my ($varname, $s, $expand);
  my %defaults = ( "CPPFLAGS" => "-I\%p/include",
		   "LDFLAGS" => "-L\%p/lib" );

  $expand = $self->{_expand};
  foreach $varname ("CC", "CFLAGS",
		    "CPP", "CPPFLAGS",
		    "CXX", "CXXFLAGS",
		    "LD", "LDFLAGS", "LIBS",
		    "MAKE", "MFLAGS") {
    if ($self->has_param("Set$varname")) {
      $s = $self->param("Set$varname");
      if (exists $defaults{$varname} and
	  not $self->param_boolean("NoSet$varname")) {
	$s .= " ".$defaults{$varname};
      }
      $ENV{$varname} = &expand_percent($s, $expand);
    } else {
      if (exists $defaults{$varname} and
	  not $self->param_boolean("NoSet$varname")) {
	$s = $defaults{$varname};
	$ENV{$varname} = &expand_percent($s, $expand);
      } else {
	delete $ENV{$varname};
      }
    }
  }
}


### EOF
1;
