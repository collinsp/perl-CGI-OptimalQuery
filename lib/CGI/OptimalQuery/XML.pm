package CGI::OptimalQuery::XML;

use strict;
use warnings;
no warnings qw( uninitialized );
use base 'CGI::OptimalQuery::Base';
use CGI();

sub output {
  my $o = shift;

  my $title = $o->{schema}->{title};
  $title =~ s/\W//g;
  my @t = localtime;
  $title .= '_'.($t[5] + 1900).($t[4] + 1).$t[3].$t[2].$t[1];

  $$o{output_handler}->($$o{httpHeader}->(-type => 'text/xml', -attachment => "$title.xml").
"<?xml version=\"1.0\"?>\n<OptimalQuery>\n");

  my @userselcols = @{ $o->get_usersel_cols };

  # print data
  while (my $rec = $o->fetch()) {
    my $buf = "<rec id=\"$$rec{U_ID}\">\n";
    foreach my $col (@userselcols) {
      $buf .= "  <$col>".$o->escape_html($o->get_val($col))."</$col>\n";
    }
    $buf .= "</rec>\n";
    $$o{output_handler}->($buf);
  }
  $$o{output_handler}->("</OptimalQuery>");
  $o->finish();
  return undef;
}


1;
