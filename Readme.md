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

 * An installed Mac OS X system, version 10.6 or later. 
   Earlier versions will not work with fink-0.36.4.1.

 * The Xcode Command Line Tools are mandatory. This package can be installed
   either by downloading it directly via developer.apple.com, through the
   Xcode application, on via the Components page of the Downloads tab of the
   Preferences on 10.7 and 10.8, or on 10.9 and 10.10 by running the `xcode-select --install` 
   command and choosing the Install button in the window that pops up, or
   you can install the full Xcode if you prefer. You may also need to use
   this command to update the tools, especially if you're having build
   problems.

   If you're doing a manual download, make sure that the tools you install
   match your Mac OS X version.

* On 10.7-10.9 you will need to install Java. Entering `javac` from a Terminal.app window should suffice to make the system download it for you, (10.7, 10.9) or open up a browser window from which you can downloadthe latest Java JDK (10.8).

* Many other things that come with Mac OS X and the Developer Tools. 
This includes `perl` and `curl`.

* Internet access. All source code is downloaded from mirror sites.

* Patience. Compiling several big packages takes time. I'm talking hours or even days here.



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

To be informed of new releases, go to [http://www.finkproject.org/lists/fink-announce.php](http://www.finkproject.org/lists/fink-announce.php) and subscribe to the
`fink-announce` mailing list. 
The list is moderated and low-traffic.

