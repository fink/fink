all:
	@echo "This is a dummy Makefile - only useful think is 'make test'"

install:
	./inject.pl

test:
	@cd t && find . -name '*.t' | xargs perl -I../perlmod -MTest::Harness -e 'runtests(@ARGV)'

.PHONY: all test install
