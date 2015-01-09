package CGI::OptimalQuery::LoadSearchTool;

use strict;
use JSON::XS();
use CGI qw(escapeHTML);

sub on_init {
  my ($o) = @_;

  # request to delete a saved search
  if ($$o{q}->param('OQdeleteSavedSearch') =~ /^\d+$/) {
    my $id = $$o{q}->param('OQdeleteSavedSearch');
    $$o{dbh}->do("DELETE FROM oq_saved_search WHERE user_id=? AND id=?", undef, $$o{schema}{savedSearchUserID}, $id);
    $$o{output_handler}->(CGI::header('text/html')."report deleted");
    return undef;
  }

  # request to load a saved search?
  elsif ($$o{q}->param('OQLoadSavedSearch') =~ /^\d+$/) {
    local $$o{dbh}->{LongReadLen};
    if ($$o{dbh}{Driver}{Name} eq 'Oracle') {
      $$o{dbh}{LongReadLen} = 900000;
      my ($readLen) = $$o{dbh}->selectrow_array("SELECT dbms_lob.getlength(params) FROM oq_saved_search WHERE id = ?", undef, $$o{q}->param('OQLoadSavedSearch'));
      $$o{dbh}{LongReadLen} = $readLen if $readLen > $$o{dbh}{LongReadLen};
    }
    my ($params) = $$o{dbh}->selectrow_array(
      "SELECT params FROM oq_saved_search WHERE id = ?",
        undef, $$o{q}->param('OQLoadSavedSearch'));
    if ($params) {
      $params = eval '{'.$params.'}'; 
      if (ref($params) eq 'HASH') {
        delete $$params{module};
        while (my ($k,$v) = each %$params) { 
          $$o{q}->param( -name => $k, -value => $v ); 
        }
      }
    }
  }
}

sub on_open {
  my ($o) = @_;
  my $ar = $$o{dbh}->selectall_arrayref("
    SELECT id, uri, user_title
    FROM oq_saved_search
    WHERE user_id = ?
    AND upper(uri) = upper(?)
    AND oq_title = ?
    ORDER BY 2", undef, $$o{schema}{savedSearchUserID},
      $$o{schema}{URI}, $$o{schema}{title});
  my $buf;
  foreach my $x (@$ar) {
    my ($id, $uri, $user_title) = @$x;
    $buf .= "<tr><td><a href=$uri?OQLoadSavedSearch=$id>".escapeHTML($user_title)."</a></td><td><button type=button class=OQDeleteSavedSearchBut data-id=$id>x</button></td></tr>";
  }
  if (! $buf) {
    $buf = "<em>none</em>";
  } else {
    $buf = "<table>".$buf."</table>";
  }
  return $buf;
}

sub activate {
  my ($o) = @_;
  $$o{schema}{tools}{loadreport} ||= {
    title => "Load Report",
    on_init => \&on_init,
    on_open => \&on_open
  };
}

1;
