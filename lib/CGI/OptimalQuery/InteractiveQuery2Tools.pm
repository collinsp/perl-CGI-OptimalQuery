package CGI::OptimalQuery::InteractiveQuery2Tools;

use strict;
use warnings;
no warnings qw( uninitialized );
use base 'CGI::OptimalQuery::Base';
use JSON::XS();

use CGI qw(escapeHTML);

sub output {
  my $o = shift;

  if ($$o{q}->param('OQsaveSearchTitle') ne '') {
    $$o{output_handler}->(CGI::header('text/html')."report saved");
    return undef;
  }
  elsif ($$o{q}->param('OQgetSavedSearch') =~ /^\d+$/) {
    my $id = $$o{q}->param('OQgetSavedSearch');
    local $$o{dbh}->{LongReadLen};
    if ($$o{dbh}{Driver}{Name} eq 'Oracle') {
      $$o{dbh}{LongReadLen} = 900000;
      my ($readLen) = $$o{dbh}->selectrow_array("SELECT dbms_lob.getlength(params) FROM oq_saved_search WHERE id = ?", undef, $id);
        $$o{dbh}{LongReadLen} = $readLen if $readLen > $$o{dbh}{LongReadLen};
    }
    my ($params) = $$o{dbh}->selectrow_array(
      "SELECT params FROM oq_saved_search WHERE id = ?", undef, $id);
    $params = eval '{'.$params.'}';
    $$o{output_handler}->(CGI::header('application/json').JSON::XS::encode_json($params));
    return undef;
  }
  elsif ($$o{q}->param('OQdeleteSavedSearch') =~ /^\d+$/) {
    my $id = $$o{q}->param('OQdeleteSavedSearch');
    $$o{dbh}->do("DELETE FROM oq_saved_search WHERE user_id=? AND id=?", undef, $$o{schema}{savedSearchUserID}, $id);
    $$o{output_handler}->(CGI::header('text/html')."report deleted");
    return undef;
  } 


  my $buf = CGI::header('text/html')."<!DOCTYPE html>
<html>
<body>
<div class=OQToolsPanel>
<fieldset>
<legend>Export Data</legend>
<label><input type=checkbox class=OQExportAllResultsInd> all results</label>
<br>
<strong>download as..</strong><br>
<a class=OQDownloadCSV href=#>CSV (Excel)</a>, 
<a class=OQDownloadHTML href=#>HTML</a>, 
<a class=OQDownloadXML href=#>XML</a>
</fieldset>\n";

  # if saved searches are enabled ..
  if ($$o{schema}{savedSearchUserID}) {
    my $ar = $$o{dbh}->selectall_arrayref("
      SELECT id, user_title
      FROM oq_saved_search
      WHERE user_id = ? 
      AND upper(uri) = upper(?)
      AND oq_title = ?", undef, $$o{schema}{savedSearchUserID},
      $$o{schema}{URI}, $$o{schema}{title});
    if ($#$ar > -1) {
      $buf .= "<fieldset>\n<legend>Load Report</legend>\n";
      foreach my $x (@$ar) {
        $buf .= "<a href=# class=OQLoadSavedSearch data-id=$$x[0]>".escapeHTML($$x[1])."</a>
<button type=button class=OQDeleteSavedSearchBut>x</button>";
      }
      $buf .= "</fieldset>\n";
    }

    $buf .= "
<fieldset>
<legend>Save Report</legend>
<label>name <input type=text class=SaveReportNameInp></label>
<button type=button class=OQSaveReportBut>save</button>
</fieldset>\n";
  }

  $buf .= "
<button class=OQToolsCancelBut type=button>cancel</button>
</div>
</body>
</html>";

  $$o{output_handler}->($buf);
}

1;
