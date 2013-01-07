Style
==========
<http://thread.gmane.org/gmane.os.apple.fink.devel/6012>

From: Max Horn \<max \<at\> quendi.de\>

Subject: Re: Basic style guide (was Re: fink/perlmod/Fink Bootstrap.pm,1.40,1.41 Command.pm,1.3,1.4 Config.pm,1.25,1.26 Mirror.pm,1.10,1.11)

Newsgroups: gmane.os.apple.fink.devel

Date: Sun, 16 Nov 2003 14:05:12 +0100


[...] Here's them, roughly:

* tabs are 4 wide
* use tabs for indention of statements (so with the above, you get "4 
character indention")
* in particular, do *not* use emacs 2/8 indention mode
* don't use tabs for indention/alignment *inside* statements.
* there is no particular reason to stick to a 80 column width, but if 
it makes you feel better, I don't mind it either, as long as it doesn't 
cause extremely unnatural code formatting
* our bracing style is:


```
    while (foo) {
    ...
    }
```


* use a whitespace after keywords:  "`if (foo)`" and not "`if(foo)`"

==========
==========

Also, all perl code should be clean under "-w" and "strict" standards. A typical perl script would thus begin:

    #!/usr/bin/perl
    # -\*- mode: Perl; tab-width: 4; -\*-
    # vim: ts=4 sw=4 noet
    use strict;
    use warnings;

==========
==========

Please try to avoid circular use/require among the perl modules, especially during their startup (BEGIN blocks, etc).

* Fink uses nothing

* Fink::Base uses nothing

* Fink::CLI uses nothing

* Fink::Checksum uses Fink::Config Fink::Services

* Fink::Checksum::MD5 uses Fink::Checksum Fink::Config

* Fink::Checksum::SHA1 uses Fink::Checksum Fink::Config

* Fink::Checksum::SHA256 uses Fink::Checksum Fink::Config

* Fink::Command uses nothing

* Fink::Config uses Fink::Base Fink::Command Fink::Services

* Fink::Configure uses Fink::Config Fink::Services Fink::CLI

* Fink::Finally uses Fink::Base

* Fink::FinkVersion uses nothing

* Fink::Mirror Fink::Services Fink::CLI Fink::Config

* Fink::NetAccess uses Fink::Services Fink::CLI Fink::Config Fink::Mirror Fink::Command Fink::FinkVersion

* Fink::Notify uses Fink::Config Fink::Services

* Fink::Notify::Growl uses Fink::Notify Fink::Config

* Fink::Notify::QuickSilver uses Fink::Notify Fink::Config

* Fink::Notify::Say uses Fink::Notify Fink::Config

* Fink::Notify::Syslog uses Fink::Notify Fink::Config

* Fink::ScanPackages uses Fink::Base Fink::CLI Fink::Command Fink::Services

* Fink::SelfUpdate::Base uses Fink::CLI Fink::Config

* Fink::Services uses Fink::Command Fink::CLI

* Fink::Status uses Fink::Config

* Fink::SysState uses Fink::CLI Fink::Config Fink::Services Fink::Status Fink::VirtPackage

* Fink::Validation uses Fink::Services Fink::Config

* Fink::VirtPackage uses Fink::Config Fink::Status

* Text::DelimMatch uses nothing (imported from CPAN)

* Text::ParseWords uses nothing (imported from CPAN)



There's a cycle here:

* Fink::Package uses Fink::Base Fink::Services Fink::CLI Fink::Config Fink::Command Fink::PkgVersion Fink::FinkVersion Fink::VirtPackage

* Fink::PkgVersion uses Fink::Base Fink::Services Fink:CLI Fink::Config Fink::NetAccess Fink::Mirror Fink::Package Fink::Status Fink::VirtPackage Fink::Bootstrap Fink::Command Fink::Notify Fink::Shlibs Fink::Validation Fink::Text::DelimMatch Fink::Text::ParseWords Fink::Checksum



These have not yet been checked for cycles:

* Fink::Finally::BuildConflicts uses Fink::CLI Fink::Config Fink::PkgVersion

* Fink::Finally::Buildlock uses Fink::Base Fink::Command Fink::Config Fink::CLI Fink::PkgVersion Fink::Services

* Fink::Bootstrap uses Fink::Config Fink::Services Fink::CLI Fink::Package Fink::PkgVersion Fink::Engine Fink::Command Fink::Checksum

* Fink::Engine Fink::Services Fink::CLI Fink::Configure Fink::Finally Fink::Finally::Buildlock Fink::Finally::BuildConflicts Fink::Package Fink::PkgVersion Fink::Config Fink::Status Fink::Command Fink::Notify Fink::Validation Fink::Checksum Fink::Scanpackages

* Fink::SelfUpdate uses Fink::Services Fink::Bootstrap Fink::CLI Fink::Config Fink::Engine Fink::Package

* Fink::SelfUpdate::CVS uses Fink::SelfUpdate::Base Fink::CLI Fink::Config Fink::Package Fink::Command Fink::Services

* Fink::SelfUpdate::point uses Fink::SelfUpdate::Base Fink::CLI Fink::Config Fink::NetAccess Fink::Command Fink::Services

* Fink::SelfUpdate::rsync uses Fink::SelfUpdate::Base Fink::CLI Fink::Config Fink::Mirror Fink::Package Fink::Command Fink::Services

* Fink::Shlibs uses Fink::Base Fink::Services Fink::CLI Fink::Config Fink::PkgVersion 


