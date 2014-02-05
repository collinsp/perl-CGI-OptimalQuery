package CGI::OptimalQuery::AbstractQuery;

use strict;
use warnings;
no warnings qw( uninitialized );
use base 'CGI::OptimalQuery::Base';

sub new {
  my $pack = shift;
  my $o = $pack->SUPER::new(@_);
  $o->sth_execute();
  return $o;
}

1;
