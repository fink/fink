# this script should only be installed when Architecture is i386
if ( $osMajorVersion > 9 ) then
  setenv VERSIONER_PERL_PREFER_32_BIT yes
endif
