package CGI::OptimalQuery::XML;

use strict;
use warnings;
no warnings qw( uninitialized );
use base 'CGI::OptimalQuery::AbstractQuery';
use CGI();

sub output {
  my $o = shift;

  my $title = $o->{schema}->{title};
  $title =~ s/\W//g;
  my @t = localtime;
  $title .= '_'.($t[5] + 1900).($t[4] + 1).$t[3].$t[2].$t[1];

  $$o{output_handler}->(CGI::header(-type => 'text/xml', -attachment => "$title.xml").
"<?xml version=\"1.0\"?><OptimalQuery>");

  # print data
  while (my $rec = $o->{sth}->fetchrow_hashref()) {
    $$o{output_handler}->("<record".(($$rec{U_ID})?" id='$$rec{U_ID}'":"").">");
    foreach my $col (sort keys %$rec) {
      my $alt = $o->escape_html($$o{schema}{select}{$col}[2]);
      next if $alt eq '';

      my $val = $rec->{$col};
      if (ref($val) eq 'ARRAY') {
        $val = join('', map { "<mval>".$o->escape_html($_)."</mval>" } @$val) 
      } else {
        $val = $o->escape_html($val);
      }
      
      $$o{output_handler}->("<$col alt='$alt'>$val</$col>");
    }
    $$o{output_handler}->("</record>");
  }
  $$o{output_handler}->("</OptimalQuery>");

  $o->{sth}->finish();
  return undef;
}


1;
