Generated from: `$Fink: install.xml,v 1.34 2012/12/15 23:48:11 alexkhansen Exp $`

 Fink 0.34.4 Installation
=========================

These are the installation instructions for the "source" distribution based on "fink-0.34.4", intended for use with OS X v.10.5 and later.

This document does not apply to the "[binary](http://www.finkproject.org/download/index.php)" distribution.

There are instructions for both first time installation and upgrading from a previous version. Fast track instructions for the impatient are at the top.


 The Fast Track
================

This section is for the impatient who don't want to take the time to learn their way around the command line world and don't care that they don't know what they're actually doing.

If you're looking for the real instructions, skip to the next section. (You can still use this section as an example.)

 Requirements
--------------
You need:

* An installed Mac OS X system, version 10.5 or later.

* Development tools. For OS X versions up to 10.6, you should install the newest version of Xcode available for your system, which can be downloaded from connect.apple.com after registering. For 10.7 and 10.8, installing the Xcode Command Line Tools is mandatory to use the most current build applications. This can be installed either by downloading it directly via connect.apple.com or through the Xcode application via the Components page of the Downloads tab of the Preferences. On 10.7 one can install an earlier monolithic Xcode (4.2.1 and earlier), but this isn't recommended.

* On 10.7 and 10.8 you will need to install Java. Entering `javac` from a Terminal.app window should suffice to make the system download it for you.

* Many other things that come with Mac OS X and the Developer Tools. 
This includes `perl` and `curl`.

* Internet access. All source code is downloaded from mirror sites.

* Patience. Compiling several big packages takes time. I'm talking hours or even days here.


First Time Installation Fast Track
------------------------------------
Start out by copying the "fink-0.34.4.tar.gz" file to your home folder (it might also show up as "fink-0.34.4.tar" if you used Safari to download it). Then, open Terminal.app and follow the session below. Computer output is in "`normal (monospaced) face`", your input is in **"bold face"** (or otherwise highlighted). The actual input prompts from the shell may vary, and some chunks of the output have been omitted ( "`...`" ).

Note: on 10.8, after you start the install process you may see dialog windows asking whether you want to install Xquartz. 
If you want to do so, go ahead. You won't have to stop the Fink install to do that.

    [frodo:~] testuser% tar xf fink-0.34.4.tar.gz
    [frodo:~] testuser% cd fink-0.34.4
    [frodo:~/fink-0.34.4] testuser% ./bootstrap

    Fink must be installed and run with superuser (root) privileges

    ...
    Choose a method: [1] 
   **1**

    sudo /Users/testuser/fink-0.34.4/bootstrap .sudo '/sw'
    Password:
   **(your normal password here)**

    ...
    OK, I'll ask you some questions and update the configuration file in
    '/sw/etc/fink.conf'.

    In what additional directory should Fink look for downloaded tarballs? [] 
   **(press return)**
   
    Which directory should Fink use to build packages? (If you don't know what this 
    means, it is safe to leave it at its default.) []
   **(press return)**
   
    Fink can set the UID and GID of its build user dynamically. Allow Fink to set the UID GID dynamically? [Y] 
   **(press return)**
   
    (1)	Quiet (do not show download statistics)
    (2)	Low (do not show tarballs being expanded)
    (3)	Medium (will show almost everything)
    (4)	High (will show everything)

    How verbose should Fink be? [2] **(press return)**

    
    Proxy/Firewall settings
    Enter the URL of the HTTP proxy to use, or 'none' for no proxy. 
    The URL should start with http:// and may contain username, password or port specifications. [none]
   **(press return)**

    Enter the URL of the proxy to use for FTP, or 'none' for no proxy.
    The URL should start with http:// and may contain username, password or port specifications. [none] 
   **(press return)**

    Use passive mode FTP transfers (to get through a firewall)? [Y/n]
   **y**
    
     Enter the maximum number of simultaneous build jobs.
     ...
     Maximum number of simultaneous build jobs: [<number of cpus>] 
**(press return)**

    Mirror selection
    Choose a continent:
    ...
   **(enter the numbers corresponding to you location)**

    ...
    Writing updated configuration to '/sw/etc/fink.conf'...
    Bootstrapping a base system via /sw/bootstrap.
    ...
   **(take a coffee break while Fink downloads and compiles the base packages)**

    ...
   
   You should now have a working Fink installation in '/sw'.
   
    [frodo:~/fink-0.34.4] testuser% cd
    [frodo:~] testuser% rm -r fink-0.34.4
    [frodo:~] testuser% /sw/bin/pathsetup.sh

The last command runs a little script to help set up your Unix paths (and other things) for use with Fink. In most cases, it will run automatically, and prompt you for permission to make changes. If the script fails, you'll have to do things by hand.

(If you need to do things by hand, and you are using `csh` or `tcsh`, you need to make sure that the command "`source /sw/bin/init.csh`" is executed during startup of your shell, either by `.login`, `.cshrc`, `.tcshrc`, or something else appropriate. If you are using `bash` or similar shells, the command you need is "`. /sw/bin/init.sh`" , and places where it might get executed include `.bashrc` and `.profile`.)

Once you have set up the paths, open a new Terminal.app window, and close all other ones. That's it, you now have a base system installed.

Before you can install additional packages, you will need to download their descriptions. 
To do this, in your new Terminal.app window, ether use:

    [frodo:~] testuser% fink selfupdate-rsync
    Password: 
   **(your normal password here)**
   
    Please note: the simple command 'fink selfupdate' should be used for routine
    updating; you only need to use a command like 'fink selfupdate-cvs' or 'fink
    selfupdate --method=rsync' if you are changing your update method.
    ...
   **(wait for the downloads to finish)**

 **(preferred)** or

    [frodo:~] testuser% fink selfupdate-cvs
    Password: 
   **(your normal password here)**

    Please note: the simple command `fink selfupdate` should be used for routine
    updating; you only need to use a command like `fink selfupdate-cvs` or `fink 
    selfupdate --method=rsync` if you are changing your update method. 
   
    fink is setting your default update method to cvs
   
    Fink has the capability to run the CVS commands as a normal user. That has some 
    advantages - it uses that user's CVS settings files and allows the package
    descriptions to be edited and updated without becoming root. Please specify the
    user login name that should be used: [<your username>] 
   **(press return)**
   
    For Fink developers only: Enter your SourceForge login name to set up full CVS
    access. Other users, just press return to set up anonymous read-only access.
    [anonymous] 
   **(press return)**
   
    Checking to see if we can use hard links to merge the existing tree. Please
    ignore errors on the next few lines.
    Now logging into the CVS server. When CVS asks you for a password, just press
    return (i.e. the password is empty).
    /usr/bin/su hansen -c 'cvs -d":pserver:anonymous@fink.cvs.sourceforge.net:/cvsroot/fink" login'
    Logging in to :pserver:anonymous@fink.cvs.sourceforge.net:2401/cvsroot/fink
    CVS password: 
   **(press return)**
   
    Logging in to :pserver:anonymous@fink.cvs.sourceforge.net:2401/cvsroot/fink
    ...
   **(wait for the downloads to finish)**

especially if you are using a proxy.

If you are using Xcode 4.3 or later, you should also run

    sudo xcodebuild -license

and enter agree so that Fink's unprivileged user can build packages that
need more than just the basic tools.

You can now install additional packages with the "`fink`" command, like this:

    [frodo:~] testuser% fink install gimp2
    sudo /sw/bin/fink 'install' 'xfree86-server' 'gimp'
    Scanning package description files..........
    Information about 6230 packages read in 1 seconds.
    
    fink needs help picking an alternative to satisfy a virtual dependency. The
    candidates:
   
    (1)	db51-aes: Berkeley DB embedded database - crypto
    (2)	db51: Berkeley DB embedded database - non crypto
   
    Pick one: [1] 
     The following package will be installed or updated:
      gimp2
    The following 308 additional packages will be installed:
     aalib aalib-bin aalib-shlibs asciidoc atk1 atk1-shlibs autoconf2.6
     automake1.11 automake1.11-core blt-dev blt-shlibs boost1.46.1.cmake
     boost1.46.1.cmake-shlibs cairo cairo-shlibs celt-dev celt-shlibs cmake
     cpan-meta-pm5124 cpan-meta-requirements-pm5124 cpan-meta-yaml-pm
     cyrus-sasl2-dev cyrus-sasl2-shlibs daemonic db51-aes db51-aes-shlibs db53-aes
     db53-aes-shlibs dbus dbus-glib1.2-dev dbus-glib1.2-shlibs dbus1.3-dev
     dbus1.3-shlibs dirac-dev dirac-shlibs docbook-bundle docbook-dsssl-ldp
     docbook-dsssl-nwalsh docbook-dtd docbook-xsl doxygen expat1 expat1-shlibs
     exporter-pm extutils-cbuilder-pm extutils-command-pm extutils-install-pm
     extutils-makemaker-pm extutils-makemaker-pm5124 extutils-manifest-pm
     file-copy-recursive-pm file-temp-pm5124 fink-package-precedence flag-sort
     fltk-x11 fltk-x11-shlibs fontconfig-config fontconfig2-dev fontconfig2-shlibs
     freeglut freeglut-shlibs freetype219 freetype219-shlibs gawk gconf2-dev
     gconf2-shlibs gd2 gd2-bin gd2-shlibs gdbm3 gdbm3-shlibs getoptbin
     gettext-tools ghostscript ghostscript-fonts giflib giflib-bin giflib-shlibs
     gimp2-shlibs glib2-dev glib2-shlibs glitz glitz-shlibs gmp5 gmp5-shlibs
     gnome-doc-utils gnutls-2.12 gnutls-2.12-shlibs graphviz graphviz-shlibs grep
     gtk+2 gtk+2-dev gtk+2-shlibs gtk-doc gtkglext1 gtkglext1-shlibs gts75
     gts75-shlibs guile18 guile18-dev guile18-libs guile18-shlibs ilmbase
     ilmbase-shlibs intltool40 iso-codes jack-dev jack-shlibs json-pp-pm lame-dev
     lame-shlibs lcms lcms-shlibs libavcodec52-shlibs libavformat52-shlibs
     libavutil50-shlibs libbabl0.1.0-dev libbabl0.1.0-shlibs libbonobo2
     libbonobo2-dev libbonobo2-shlibs libcelt0.2-dev libcelt0.2-shlibs libcroco3
     libcroco3-shlibs libdatrie1 libdatrie1-shlibs libexif12 libexif12-shlibs
     libflac8 libflac8-dev libgcrypt libgcrypt-shlibs libgegl0.1.0-dev
     libgegl0.1.0-shlibs libgettext3-dev libgettext3-shlibs libgettextpo2-dev
     libgettextpo2-shlibs libglade2 libglade2-shlibs libgmpxx5-shlibs libgpg-error
     libgpg-error-shlibs libgsf1.114-dev libgsf1.114-shlibs libgsm1-dev
     libgsm1-shlibs libhogweed-shlibs libidl2 libidl2-shlibs libidn libidn-shlibs
     libjasper.1 libjasper.1-shlibs libjpeg libjpeg-bin libjpeg-shlibs libjpeg8
     libjpeg8-shlibs liblzma5 liblzma5-shlibs libming1-dev libming1-shlibs libmng2
     libmng2-shlibs libncursesw5 libncursesw5-shlibs libogg libogg-shlibs
     liboil-0.3 liboil-0.3-shlibs libopencore-amr0 libopencore-amr0-shlibs
     libopenexr6-shlibs libopenjpeg libopenjpeg-shlibs libopenraw1-dev
     libopenraw1-shlibs libpaper1-dev libpaper1-shlibs libpcre1 libpcre1-shlibs
     libpng14 libpng14-shlibs libpng15 libpng15-shlibs libpng3 libpng3-shlibs
     librarian.08-shlibs librsvg2 librsvg2-shlibs libschroedinger
     libschroedinger-shlibs libsigsegv2 libsigsegv2-shlibs libsndfile1-dev
     libsndfile1-shlibs libsoup2.4.1-ssl libsoup2.4.1-ssl-shlibs libspeex1
     libspeex1-shlibs libspiro0 libspiro0-shlibs libtasn1-3 libtasn1-3-shlibs
     libthai libthai-dev libthai-shlibs libtheora0 libtheora0-shlibs
     libtheoradec1-shlibs libtheoraenc1-shlibs libtiff libtiff-bin libtiff-shlibs
     libtool2 libtool2-shlibs libvorbis0 libvorbis0-shlibs libvpx libwmf
     libwmf-shlibs libx264-115-dev libx264-115-shlibs libxml2 libxml2-bin
     libxml2-py27 libxml2-shlibs libxslt libxslt-bin libxslt-shlibs lua51 lua51-dev
     lua51-shlibs lynx m4 nasm netpbm10 netpbm10-shlibs nettle4a nettle4a-shlibs
     ocaml openexr openexr-dev openjade openldap24-dev openldap24-shlibs opensp-bin
     opensp5-dev opensp5-shlibs openssl100-dev openssl100-shlibs orbit2 orbit2-dev
     orbit2-shlibs pango1-xft2-ft219 pango1-xft2-ft219-dev pango1-xft2-ft219-shlibs
     parse-cpan-meta-pm passwd-core passwd-messagebus pixman pixman-shlibs
     pkgconfig poppler-data poppler4 poppler4-glib poppler4-glib-shlibs
     poppler4-shlibs popt popt-shlibs python27 python27-shlibs rarian rarian-compat
     readline5 readline5-shlibs readline6 readline6-shlibs sdl sdl-shlibs
     sgml-entities-iso8879 shared-mime-info sqlite3-dev sqlite3-shlibs swig
     system-openssl-dev tcltk tcltk-dev tcltk-shlibs test-harness-pm5124
     test-simple-pm5124 texi2html texinfo version-pm5124
     version-requirements-pm5124 xdg-base xft2-dev xft2-shlibs xinitrc
     xml-parser-pm5124 xmlto xvidcore xvidcore-shlibs xz yasm
    The following 2 packages might be temporarily removed:
     lcms tcltk-dev
    Do you want to continue? [Y/n]
    ...

If these instructions don't work for you, well, you'll have to take the time to read through the rest of this document and the [online FAQ](http://www.finkproject.org/faq/). You can also ask on the [fink-users mailing list](http://www.finkproject.org/lists/fink-users.php), but expect to be pointed back at the documentation when your problem actually is well-documented.

 First Time Installation
=========================
 Requirements
--------------

You need:

* Development tools. For OS X versions up to 10.6, you should install the newest version of Xcode available for your system, which can be downloaded from connect.apple.com after registering. For 10.7 and 10.8, installing the Xcode Command Line Tools is mandatory to use the most current build applications. This can be installed either by downloading it directly via connect.apple.com or through the Xcode application via the Components page of the Downloads tab of the Preferences. On 10.7 one can install an earlier monolithic Xcode (4.2.1 and earlier), but this isn't recommended.

* On 10.7 and 10.8 you will need to install Java. Entering `javac` from a Terminal.app window should suffice to make the system download it for you.

* Many other things that come with Mac OS X and the Developer Tools. This includes `perl` and `curl`.

* Internet access. All source code is downloaded from mirror sites.

* Patience. Compiling several big packages takes time. I'm talking hours or even days here.


Choosing A Directory
----------------------
Before you install, you must decide where Fink's directory hierarchy will live. The recommended place is /sw, and all examples in this document will use that. Any other directory should be fine as well, as long as you don't use existing directories like /usr/local or /usr. The bootstrap script tries to catch these.

If you intend to use the binary distribution (through `apt-get` / `dselect`), you must install to /sw. Unfortunately, binary packages are not relocatable.

The directory that you choose must not contain any spaces or similar. Both Unix itself and the bulk of Unix software were written under this assumption. Using symlinks to trick the bootstrap script simply won't work.

A special note about /usr/local: While it is possible to install Fink in /usr/local (and the bootstrap script will let you do that after a confirmation), it is a bad idea. Many third party software packages install into /usr/local. This can cause severe problems for Fink, including overwriting files, `dpkg` refusing to install packages and strange build errors. Also, the /usr/local hierarchy is in the default search path for the shell and the compiler. That means that it is much more difficult to get back to a working system when things break. You have been warned.


Installation
--------------
First, you need to unpack the fink-0.34.4.tar.gz tarball (it might also show up as "fink-0.34.4.tar" if you used Safari to download it). So, in a terminal window, go to the directory where you put the tarball, and run this command:

    tar xf fink-0.34.4.tar.gz

You now have a directory named fink-0.34.4. Change to it with "`cd fink-0.34.4`".

The actual installation is performed by the perl script `bootstrap`. So, to start installation, go to the fink-0.34.4 directory and run this command:

    ./bootstrap

After running some tests, the script will ask you what method should be used to gain root privileges. The most useful choice is '`sudo`'. On a default install of Mac OS X, `sudo` is already enabled for the user account created during installation. The script will immediately use the method you choose to become root. This is required for the installation.

Next, the script will ask you for the installation path. See 'Choosing A Directory' above for hints about this. The script will create the directory and set it up for the bootstrap that will be done later.

Next up is Fink configuration. The process should be self-explaining. You will be asked how you want to set up fink's build user account. If you are on a networked system where the users and groups are on a central server, you can select the parameters manually--check with your network administrator as to what to use. You will also be asked about proxies -- again, check with your network administrator, and to select mirror sites for downloads. If you don't know what to say, you can just press Return and Fink will use a reasonable default value.

Finally, the script has enough information to conduct the bootstrap process. That means it will now download, build and install some essential packages. Don't worry if you see some packages being compiled twice. This is required because to build a binary package of the package manager, you first must have the package manager available.

Note: on 10.8, after you start the install process you may see dialog windows asking whether you want to install Xquartz. If you want to do so, go ahead. You won't have to stop the Fink install to do that.

After the bootstrap procedure finishes, run "`/sw/bin/pathsetup.sh`" to help set up your shell environment for use with Fink. In most cases, it will run automatically, and prompt you for permission to make changes. If the script fails, you'll have to do things by hand (see below).

(If you need to do things by hand, and you are using `csh` or `tcsh`, you need to make sure that the command "`source /sw/bin/init.csh`" is executed during startup of your shell, either by `.login`, `.cshrc`, `.tcshrc`, or something else appropriate. If you are using `bash` or similar shells, the command you need
is "`. /sw/bin/init.sh`" , and places where it might get executed include `.bashrc` and `.profile`.)

Once your environment is set up, start a new terminal window to ensure that the changes get implemented. You will now need to have Fink download package descriptions for you.

You can use

    fink selfupdate-rsync

to download package descriptions using `rsync`. This is the preferred option for most users, since it is quick and there are multiple mirror sites available.

However, `rsync` is often blocked by network administrators. If your firewall doesn't allow you to use `rsync`, then you can try

    fink selfupdate-cvs

to download package descriptions using `cvs`. If you have an HTTP proxy set up, `fink` will pass its information along to `cvs`. Note: you can only use anonymous cvs (pserver) through a proxy.

If you are using Xcode 4.3 or later, you should also run

    sudo xcodebuild -license

and enter agree so that Fink's unprivileged user can build packages that need more than just the basic tools.

You can now use "`fink`" commands to install packages.

    fink --help

is a useful place to get more information about how to use "`fink`" .


 Getting X11 Sorted Out
------------------------
Fink uses virtual packages to declare dependencies on X11. As of OS 10.5, we don't provide any packages of our own. The supported options are:

* 10.5: Either Apple's standard X11 or XQuartz-2.6.3 or earlier. Note: if
   you install XQuartz-2.4 or later you will quite likely need to reinstall
   Fink if you update to 10.6.

* 10.6: Only Apple's standard X11, since XQuartz installs in a different
   directory tree ("/opt/X11") than the standard X11 ("/usr/X11") for
   10.6 and later so that they can coexist.

* 10.7: Only Apple's standard X11.

* 10.8: Only Xquartz 2.7 and later.

For more information on installing and running X11, refer to the online X11
on Darwin and Mac OS X document [http://www.finkproject.org/doc/x11/](http://www.finkproject.org/doc/x11/).

 Upgrading Fink
================

You can update Fink with the built-in '`selfupdate`' command. Note: this is not guaranteed to be sufficient if you updated OS X.

Updating The Package Manager
------------------------------
To update Fink, run the following command:

    fink selfupdate

This will automatically update your existing Fink installation to use the latest package manager, and also update all essential packages. However, it will not update any other packages.


Updating Packages
-------------------
The above updating steps will not update the actual packages, they only provide you with the means to do so. The easiest way to get the new packages is to use the 'update-all' command:

    fink update-all

This will bring all installed packages to the latest version. If you don't want to do this (it may take some time), you can update individual packages with the 'update' command.


 Clean Upgrade
===============

 There are situations, which normally don't come up every day, in which you
may find that you need to install Fink over again.


 Situations Calling for a Clean Reinstall
------------------------------------------
* You want to switch architectures, e.g. you have a 32-bit (i386) Fink distribution on OS 10.6, and you would like to have a 64-bit (x86_64) one instead. This also applies if you try to migrate a PowerPC OS X setup to an Intel machine.

* You want to move Fink to a different path.

* You want to update, or have already updated, OS X between versions where Fink doesn't support an upgrade path:

- 10.4 -> 10.6+

- 10.5 -> 10.7+

- 10.6 -> 10.7+

* You have updated from 10.5 to 10.6 with XQuartz-2.4 or later installed, and X11-based libraries and executables stop working.

* Your Fink installation has linked to libraries, e.g. from MacPorts or
   "/usr/local", which have been removed from your machine, resulting in
   breakage in your Fink libraries and executables.


Backing up to save time
-------------------------
To save time after you have reinstalled Fink, you can get a transcript of your installed packages. The following command in a terminal window will work, even if for some reason the Fink tools aren't functioning:


    grep -B1 "install ok installed" /sw/var/lib/dpkg/status \
    | grep "^Package:" | cut -d: -f2 | cut -d\  f2 > finkinst.txt


This will save the list of your packages in the file "finkinst.txt" in the current working directory.

You may also want to copy or move the sources in "/sw/src" to another location so that you don't have to spend time downloading them when you begin restoring your Fink distribution.

In addition, if you have made global configuration changes to any of your packages by editing configuration files in "/sw/etc", then you may wish to back those up.


 Removing Your Old Fink
------------------------
Once you've backed everything up, you are ready to remove your Fink distribution. You can remove "/sw" as well as anything in "/Applications/Fink" using the Finder or the command line:

    sudo rm -rf /sw /Applications/Fink/*

(Replace "/sw" by your actual Fink tree).


 Installing Fink Again
-----------------------
First, follow the first-time install instructions.

Once you have downloaded package descriptions, you can put the sources that you backed up into "/sw/src" either using the Finder or the command line:

    sudo cp /path/to/backup/* /sw/src

(As usual, replace "/sw" with your Fink tree). If you prefer, you can use "`fink configure`" to specify your backup location:

    In what additional directory should Fink look for downloaded tarballs? [] 
   **(enter your backup directory at the prompt)**

Note: this requires that the entire path to and including your backup directory is world-readable.

You can also restore your global configuration files at this time. Note: we recommend that you not restore "/sw/etc/fink.conf" from your prior installation of Fink, to avoid incompatibilities. You can open it up in a text editor and enter the corresponding values into "`fink configure`".

