package CGI::OptimalQuery::InteractiveQuery2Tools;

use strict;
use warnings;
no warnings qw( uninitialized );
use base 'CGI::OptimalQuery::Base';
use JSON::XS();

use CGI qw(escapeHTML);

sub output {
  my $o = shift;

  # some legacy action handling
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

  # call tool handler
  else {
    my $openedtool = $$o{q}->param('tool');
    my $tool = $$o{schema}{tools}{$openedtool};

    if (! $tool || ! $$tool{handler}) {
      $$o{output_handler}->(CGI::header('text/html')."<!DOCTYPE html>\n<html><body>could not find tool</body></html>");
      return undef;
    }

    my $buf = $$tool{handler}->($o);
    $$o{output_handler}->(CGI::header('text/html')."<!DOCTYPE html>\n<html><body>".$buf."</body></html>") if $buf;
    return undef;
  }
}

1;
