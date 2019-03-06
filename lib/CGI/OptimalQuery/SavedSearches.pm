package CGI::OptimalQuery::SavedSearches;

use strict;
use warnings;
no warnings qw( uninitialized redefine );
use CGI::OptimalQuery::Base();

# static accessor deprecated - do not used in new code instead
#   my $oq = new CGI::OptimalQuery(\%schema);   # note: no need to provide joins, select, ets
#   $oq->get_saved_searches_html();
sub get_html {
  my $o = bless {}, 'CGI::OptimalQuery::Base';
  ($$o{q}, $$o{dbh}, $$o{schema}{savedSearchUserID}) = @_;
  return $o->get_saved_searches_html();
}
  
1;
