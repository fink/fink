PREFIX=/sw
VERSION=`cat VERSION`
TEST_BASEPATH=$(PWD)/t/basepath

all:
	@echo    "usage: $(MAKE) <target>"
	@echo    ""
	@echo -e "\tcommit      commit your changes"
	@echo -e "\tbootstrap   install a fresh fink installation"
	@echo -e "\t            PREFIX can be set, defaults to /sw"   
	@echo -e "\tinstall     install to an existing fink installation"
	@echo -e "\ttest        perform tests on the fink code"
	@echo    ""

commit: test
	@cvs commit

bootstrap: test
	@sh bootstrap.sh $(PREFIX)

install:
	./inject.pl

test_setup:
	@./setup.sh $(TEST_BASEPATH)

test: test_setup
	@cd t && ./testmore.pl || find . -name '*.t' | xargs /usr/bin/perl -I../perlmod -MTest::Harness -e 'runtests(@ARGV)'

.PHONY: all test install
