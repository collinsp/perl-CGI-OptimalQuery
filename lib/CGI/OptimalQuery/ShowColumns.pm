package CGI::OptimalQuery::ShowColumns;

use strict;
use warnings;
no warnings qw( uninitialized );
use base 'CGI::OptimalQuery::Base';
use CGI qw(escapeHTML);

sub output {
  my $o = shift;
  my $buf = CGI::header('text/html').
"<!DOCTYPE html>
<html>
<body>
<div class=OQAddColumnsPanel>
<h1>select fields to add ..</h1>";
  my $s = $$o{schema}{select};
  my @c = sort { $$s{$a}[2] cmp $$s{$b}[2] } keys %$s;
  foreach my $colAlias (@c) {
    my $label = $$s{$colAlias}[2];
    my $colOpts = $$s{$colAlias}[3];
    $buf .= '<label><input type=checkbox value="'.escapeHTML($colAlias).'">'
      .escapeHTML($label).'</label>'
      unless $label eq '' || $$colOpts{disable_select} || $$colOpts{is_hidden};
  }
  $buf .= "
<br>
<button class=OQAddColumnsCancelBut>cancel</button>
<button class=OQAddColumnsOKBut>ok</button>
</div>
</body>
</html>";
  $$o{output_handler}->($buf);
  return undef;
}

1;
