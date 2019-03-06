package CGI::OptimalQuery::LoadSearchTool;

use strict;
use CGI::OptimalQuery::SavedSearches();
use JSON::XS();
use CGI::OptimalQuery::Base();

sub escapeHTML { CGI::OptimalQuery::Base::escapeHTML(@_) }

sub load_default_saved_search {
  my ($o) = @_;
  return undef unless exists $$o{canSaveDefaultSearches};
  local $$o{dbh}{LongReadLen};
  if ($$o{dbh}{Driver}{Name} eq 'Oracle') {
    $$o{dbh}{LongReadLen} = 900000;
    my ($readLen) = $$o{dbh}->selectrow_array("SELECT dbms_lob.getlength(params) FROM oq_saved_search WHERE uri=? AND is_default=1", undef, $$o{schema}{URI});
    $$o{dbh}{LongReadLen} = $readLen if $readLen > $$o{dbh}{LongReadLen};
  }
  my ($params) = $$o{dbh}->selectrow_array("
    SELECT params
    FROM oq_saved_search
    WHERE uri=?
    AND is_default=1", undef, $$o{schema}{URI});

  if ($params) {
    $params = eval '{'.$params.'}'; 
    if (ref($params) eq 'HASH') {
      delete $$params{module};
      while (my ($k,$v) = each %$params) {
        if(!defined($$o{q}->param($k))) {
          $$o{q}->param( -name => $k, -values => $v ); 
        }
      }
    }
  }
  return undef;
}


sub load_saved_search {
  my ($o, $id) = @_;
  die "invalid ID" unless $id =~ /^\d+$/;
  local $$o{dbh}{LongReadLen};
  if ($$o{dbh}{Driver}{Name} eq 'Oracle') {
    $$o{dbh}{LongReadLen} = 900000;
    my ($readLen) = $$o{dbh}->selectrow_array("SELECT dbms_lob.getlength(params) FROM oq_saved_search WHERE id = ?", undef, $id);
    $$o{dbh}{LongReadLen} = $readLen if $readLen > $$o{dbh}{LongReadLen};
  }
  my ($params, $report_uri) = $$o{dbh}->selectrow_array(
    "SELECT params, uri FROM oq_saved_search WHERE id=?", undef, $id);
  die "NOT_FOUND - saved search is not longer available\n" if $params eq '';
  $params = eval '{'.$params.'}'; 

  # if no report config, redirect user to report
  if (! $$o{schema}{joins}) {
    my $url = $report_uri.'?OQss='.$id;
    if (ref($params) eq 'HASH') {
      while (my ($k,$v) = each %$params) {
        next if $k eq 'module';
        if (ref($v) eq 'ARRAY') {
          $url .= '&'.$k.'='.$o->escape_uri($_) for @$v;
        } else {
          $url .= '&'.$k.'='.$o->escape_uri($v);
        }
      }
    }
    my $buf = $$o{schema}{httpHeader}->( -status => 303, -uri => $url );
    $$o{schema}{output_handler}->($buf);
  }

  # report URI is correct, make sure we load saved search setting for this URL
  else {
    $$o{q}->param('OQss', $id);
    if (ref($params) eq 'HASH') {
      while (my ($k,$v) = each %$params) {
        next if $k eq 'module';
        $$o{q}->param( -name => $k, -values => $v ) unless defined($$o{q}->param($k));
      }
    }
  }

  return undef;
}

sub on_init {
  my ($o) = @_;

  my $delete_id = $$o{q}->param('OQDeleteSavedSearch') || $$o{q}->url_param('OQDeleteSavedSearch');

  # request to delete a saved search
  if ($delete_id) {
    $o->csrf_check();
    $$o{dbh}->do("DELETE FROM oq_saved_search WHERE user_id=? AND id=?", undef, $$o{schema}{savedSearchUserID}, $delete_id);
    $$o{output_handler}->($$o{httpHeader}->('text/html')."report deleted");
    return undef;
  }

  # request to load a saved search?
  elsif ($$o{q}->param('OQLoadSavedSearch') =~ /^(\d+)$/) {
    die "BAD_PRIV - cannot load a saved search as a guest user\n" unless $$o{schema}{savedSearchUserID};
    load_saved_search($o, int($1));
  }

  # if intial request, load default saved search if it exists
  elsif (! defined $$o{q}->param('module')) {
    load_default_saved_search($o);
  }
}

sub on_open {
  my ($o) = @_;
  my $buf = $o->get_saved_searches_html( oq_title => $$o{schema}{title}, uri => $$o{schema}{URI}, hide_title => 1 );
  $buf ||= '<em>none</em>';
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
