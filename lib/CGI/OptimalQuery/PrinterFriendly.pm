package CGI::OptimalQuery::PrinterFriendly;

use strict;
use warnings;
no warnings qw( uninitialized );
use base 'CGI::OptimalQuery::AbstractQuery';
use POSIX qw( strftime );

sub output {
  my $o = shift;

  my $doc;

  my $date = strftime "%a. %b %e %Y", localtime;

  my $title = $o->{schema}->{title};
  $title =~ s/\W//g;
  my @t = localtime;
  $title .= '_'.($t[5] + 1900).($t[4] + 1).$t[3].$t[2].$t[1];

  $doc .= $$o{q}->header(-type => 'text/html', -attachment => "$title.html");
  $doc .= <<TILEND;
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" 
"DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<body style="margin: 0; background-color: white;">
<div id='OQdoc'>
<style id='OQstyle'>

BODY { width: 650px; }

#OQtitle { font-weight: bold; }
#OQsummary { font-style: italic; }
#OQhead { width: 100%; }
#OQhead td { width: 33%; font-size: 16px; }

.OQinfoName { font-size: 16px; font-weight: bold; }



.OQcolHeader { font-size: 16px; font-weight: bold; }
#OQdata { width: 100%; border-top: 2px solid #666666; }
#OQdata tr td { border-bottom: 1px solid #666666; border-right: 1px solid #666666; }

</style>
TILEND

  $doc .= "

<table id='OQhead'>
<tr>
<td id='OQtitle'>".$o->escape_html($o->get_title)."</td>
<td id='OQsummary'>Result(s) (".$o->commify($o->get_lo_rec)." - ".$o->commify($o->get_hi_rec).") of ".$o->commify($o->get_count)."</td>
<td id='OQdate'>$date</td>
</tr>
</table>

<table id='OQinfo'>";

  my $val = $o->escape_html($$o{queryDescr});
  $doc .= "<tr id='OQqueryDescr'><td class='OQinfoName'>Query:</td><td class='OQinfoVal'>$val</td></tr>" if $val ne '';
  $val = $o->escape_html($o->get_filter());
  $doc .= "<tr id='OQfilter'><td class='OQinfoName'>Filter:</td><td class='OQinfoVal'>$val</td></tr>" if $val ne '';
  $val = $o->escape_html($o->get_sort());
  $doc .= "<tr id='OQsort'><td class='OQinfoName'>Sort:</td><td class='OQinfoVal'>$val</td></tr>" if $val ne '';
  $doc .= "
</table>


<table id='OQdata'>
<thead>
<tr>";

  foreach my $i (0 .. ($o->get_num_usersel_cols() - 1)) {
    my $colAlias = $o->get_usersel_cols->[$i];
    my $nice = $o->get_nice_name($colAlias) || '!! UNKNOWN !!';
    $doc .= "<td class='OQcolHeader'>".$o->escape_html($nice)."</td>";
  }

  $doc .= "
</tr>
</thead>

<tfoot>
</tfoot>

<tbody>";

  $$o{output_handler}->($doc);
  $doc = '';
  my $i = 0;

  # print data
  my $rowType = 'Odd';

  while (my $r = $o->{sth}->fetchrow_hashref()) {
    $i++;
    my $class = "OQdataRowType$rowType";
    $doc .= "<tr class='$class'>\n";

    # print table cell with value
    foreach my $col (@{ $o->get_usersel_cols }) {
      my $val;
      if (ref($$r{$col}) eq 'ARRAY') {
        $val = join(', ', map { $o->escape_html($_) } @{ $$r{$col} }); 
      } else {
        $val = $o->escape_html($$r{$col});
      }
      $val = '&nbsp;' if $val eq '';
      $doc .= "<td class='OQcolData'>$val</td>\n";
    }

    $doc .= "\n</tr>\n\n";

    $rowType = ($rowType eq "Odd") ? "Even" : "Odd";

    if ($i == 500) { $$o{output_handler}->($doc); $doc = ''; $i=0; }
  }
  $$o{output_handler}->($doc);
  $o->{sth}->finish();

  $doc .= "
</tbody>
</table>
</body>
</html>";

  return undef;
}

1;
