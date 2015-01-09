package CGI::OptimalQuery::CustomOutput;

use strict;
use warnings;
no warnings qw( uninitialized );
use base 'CGI::OptimalQuery::AbstractQuery';
use CGI();

our $custom_output_handler;

sub output {
  my $o = shift;
  my $codeRef = $$o{custom_output_handler} || $custom_output_handler;
  $codeRef->($o) if $codeRef;
}

1;
