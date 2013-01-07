Generated from: `$Fink: readme.en.xml,v 1.4 2006/09/16 23:17:53 dmrrsn Exp $`

Fink ReadMe
=============

This is Fink, a package management system that aims to bring the full world of Open Source software to Darwin and Mac OS X.

With the help of `dpkg`, it maintains a separate directory hierarchy. 
It downloads original source releases, patches them if necessary, configures them for Darwin and compiles and installs them. 
The information about available packages and the necessary patches (the "package descriptions") are maintained separately, but are usually included with this distribution.
The actual source code is downloaded from the Internet as necessary.

Although Fink cannot be considered "mature" and it has some rough edges and lacking features, it is successfully used by a large number of people.
Please read the instructions carefully and don't be surprised if something doesn't work as expected. 
There are good explanations for most failures; check the website if you need help.

Fink is released under the terms of the GNU General Public License. 
See the file `COPYING` for details.


Requirements
--------------

You need:

 * An installed Mac OS X system, version 10.0 or later. 
   (There may still be some stray linker-related problems with 10.1.) 
   Darwin 1.3.1 should also work, but this has not been tested. 
   Earlier versions of both will not work.

 * Development tools. 
   On Mac OS X, install the Developer.pkg package from the Developer Tools CD. 
   (If on 10.7 or later, download Xcode from the Mac App Store, and then install the "Command Line Tools for Xcode" from Xcode's preferences.) 
   Make sure that the tools you install match your Mac OS X version. 
   On Darwin, the tools should be present in the default install.

 * Internet access. All source code is downloaded from mirror sites.

 * Patience. Compiling several big packages takes time. 
   I'm talking hours or even days here.



Installation
--------------
The installation process is described in detail in the file `INSTALL`. 
Please read it first, the process is non-trivial. 
It also describes the upgrade procedure.



Using Fink
------------
The file `USAGE` describes how to set your paths and how to install and remove packages. 
It also has a complete list of available commands.



Further Questions?
--------------------
If the documentation included here doesn't answer your question, stroll over to the Fink website at [http://www.finkproject.org/](http://www.finkproject.org/) and check out the Help page there: [http://www.finkproject.org/help/](http://www.finkproject.org/help/). 
It will point you at the other documentation that is available and sources for support if you need it.

If you'd like to contribute to Fink, the Help page mentioned above also has a list of things you can do, like testing or creating packages.



Staying Informed
------------------
The project's website is at [http://www.finkproject.org/](http://www.finkproject.org/).

To be informed of new releases, go to [http://www.finkproject.orgt/lists/fink-announce.php](http://www.finkproject.org/lists/fink-announce.php) and subscribe to the
`fink-announce` mailing list. 
The list is moderated and low-traffic.

