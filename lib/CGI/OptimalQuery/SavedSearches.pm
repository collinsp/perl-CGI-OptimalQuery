package CGI::OptimalQuery::SavedSearches;

use strict;
use warnings;
no warnings qw( uninitialized );
use CGI qw( escapeHTML );

sub process_request {
  my ($q,$dbh,$userid,$selfurl) = @_;

  if ($q->param('load') =~ /^(\d+)$/) {
    my $id = $1;
    my $oracleReadLen;
    if ($$dbh{Driver}{Name} eq 'Oracle') {
      ($oracleReadLen) = $dbh->selectrow_array("SELECT max(dbms_lob.getlength(params)) FROM oq_saved_search WHERE user_id = ?", undef, $userid);
    }
    local $dbh->{LongReadLen} = $oracleReadLen
      if $oracleReadLen && $oracleReadLen > $dbh->{LongReadLen};

    my $sth = $dbh->prepare("SELECT uri, params FROM oq_saved_search WHERE id=? AND user_id = ?");
    $sth->execute($id, $userid);
    my ($uri, $params) = $sth->fetchrow_array();

    if (! $uri) {
      print CGI::header("text/plain"), "saved search not found";
      return undef;
    } else {
      my $stateArgs = '';
      if ($params ne '') {
        $params = eval '{'.$params.'}';
        $$params{module} = 'InteractiveQuery2';
        if (ref($params) eq 'HASH') {
          delete $$params{show};
          delete $$params{rows_page};
          delete $$params{page};
          delete $$params{hiddenFilter};
          delete $$params{filter};
          delete $$params{queryDescr};
          delete $$params{sort};
          while (my ($k,$v) = each %$params) {
            $stateArgs .= "&$k=";
            $stateArgs .= (ref($v) eq 'ARRAY') ? CGI::escape($$v[0]) : CGI::escape($v);
          }
        }
      }
      print CGI::redirect("$uri?OQLoadSavedSearch=".$id.$stateArgs);
      return undef;
    }
  }

  elsif ($q->param('delete') =~ /^(\d+)$/) {
    my $id = $1;
    $dbh->do("DELETE FROM oq_saved_search WHERE id=? AND user_id=?", undef, $id, $userid);
    print CGI::header('text/plain'), "OK";
    return undef;
  }

  else {
    print CGI::header('text/plain'), get_html($q,$dbh,$userid,$selfurl);
    return undef;
  }

  return undef;
}

sub get_html {
  my ($q,$dbh,$userid,$selfurl) = @_;

  local $$dbh{FetchHashKeyName} = 'NAME_uc';

  my $sth = $dbh->prepare(
    "SELECT *
     FROM oq_saved_search
     WHERE user_id=?
     ORDER BY oq_title, user_title");
  $sth->execute($userid);
  my $last_oq_title = '';
  my $buf = '';
  while (my $h = $sth->fetchrow_hashref()) {
    next if $$h{IS_DEFAULT};
    if ($last_oq_title ne $$h{OQ_TITLE}) {
      $buf .= '</ul>' if $last_oq_title;
      $last_oq_title = $$h{OQ_TITLE};
      $buf .= "<h4>".escapeHTML($$h{OQ_TITLE})."</h4><ul>";
    }
    $buf .= "<li>
<a href='".escapeHTML("$$h{URI}?OQLoadSavedSearch=$$h{ID}")."' title='load saved search' class='opwin oqssload'>".escapeHTML($$h{USER_TITLE})."</a>
<button type=button title='delete saved search' class=oqssdelete data-url='".escapeHTML("$$h{URI}?OQdeleteSavedSearch=$$h{ID}")."'>&#10005;</button>
</li>";
  }
  $buf .= '</ul>' if $last_oq_title;

  if ($buf) {
    $buf = '<div id=loadsavedsearches>'.$buf.'</div>
<script>
$("#loadsavedsearches").on("click", ".oqssdelete", function(){
  var $t = $(this);
  var $li = $t.closest("li");
  $.ajax({
    type: "post",
    url: $t.attr("data-url"),
    success: function() {
      if ($li.siblings().length==0) {
        var $ul = $li.parent();
        $ul.add($ul.prev("h4")).remove();
      }
      else {
        $li.remove();
      }
    }
  });
  return false;
});
</script>';
  }
  return $buf;
}
1;
