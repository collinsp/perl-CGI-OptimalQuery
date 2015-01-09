package CGI::OptimalQuery::SaveSearchTool;

use strict;
use Data::Dumper;
use Mail::Sendmail();
use CGI qw( escapeHTML );

# specify max character threshold after which report rows are now outputted in email
my $TRUNC_REPORT_CHAR_LIMIT = 500000;   # ~ .5MB allowed per report

# specify maximum rows allowed to be procssed by saved search alerts
# warning: don't set this too high
# all uids are stored in oq_saved_search.alert_uids field
# this field is then consulted to determine when new records are added/removed
my $MAX_ROWS = 1000;

sub on_init {
  my ($o) = @_;

  # request to save a search?
  if ($$o{q}->param('OQsaveSearchTitle') ne '') {

    # delete old searches with this user, title, uri
    $$o{dbh}->do("DELETE FROM oq_saved_search WHERE user_id = ? AND uri = ? AND oq_title = ? AND user_title = ?", undef, $$o{schema}{savedSearchUserID}, $$o{schema}{URI},$$o{schema}{title}, $$o{q}->param('OQsaveSearchTitle'));

    $$o{q}->param('queryDescr', $$o{q}->param('OQsaveSearchTitle'));

    # serialize params
    my $params;
    { my %data;
      foreach my $p (qw( show filter sort page rows_page queryDescr hiddenFilter )) {
        $data{$p} = $$o{q}->param($p);
      }
      if (ref($$o{schema}{state_params}) eq 'ARRAY') {
        foreach my $p (@{ $$o{schema}{state_params} }) {
          my @v = $$o{q}->param($p);
          $data{$p} = \@v;
        }
      }

      local $Data::Dumper::Indent = 0;
      local $Data::Dumper::Quotekeys = 0;
      local $Data::Dumper::Pair = '=>';
      local $Data::Dumper::Sortkeys = 1;
      $params = Dumper(\%data);
      $params =~ s/^[^\{]+\{//;
      $params =~ s/\}\;\s*$//;
    }

    my (@cols,@vals,@binds);

    if ($$o{dbh}{Driver}{Name} eq 'Oracle') {
      push @cols, "id";
      push @vals, 's_oq_saved_search.nextval';
    }
    push @cols, "user_id";
    push @vals, '?';
    push @binds, $$o{schema}{savedSearchUserID};

    push @cols, "uri";
    push @vals, '?';
    push @binds, $$o{schema}{URI};

    push @cols, "oq_title";
    push @vals, '?';
    push @binds, $$o{schema}{title};

    push @cols, "user_title";
    push @vals, '?';
    push @binds, scalar($$o{q}->param('OQsaveSearchTitle'));

    push @cols, "params";
    push @vals, '?';
    push @binds, $params;
  
    push @cols, "alert_mask";
    push @vals, '?';
    push @binds, scalar($$o{q}->param('alert_mask')) || 0;

    # if user requested to be notified on new matches
    if ($$o{q}->param('alert_mask') > 0) {
      push @cols, "alert_interval_min";
      push @vals, '?';
      push @binds, scalar($$o{q}->param('alert_interval_min'));

      push @cols, "alert_dow";
      push @vals, '?';
      push @binds, scalar($$o{q}->param('alert_dow'));

      push @cols, "alert_start_hour";
      push @vals, '?';
      push @binds, scalar($$o{q}->param('alert_start_hour'));

      push @cols, "alert_end_hour";
      push @vals, '?';
      push @binds, scalar($$o{q}->param('alert_end_hour'));

      push @cols, "alert_uids";
      push @vals, '?';
      push @binds, "##NOTPOPULATED##";
    }

    my $sql = "INSERT INTO oq_saved_search (".join(',',@cols).") VALUES (".join(',', @vals).")";
    $$o{dbh}->do($sql, undef, @binds);

    $$o{output_handler}->(CGI::header('text/html')."report saved");
    return undef;
  }
}


sub on_open {
  my ($o) = @_;
  my $buf = "<label>name <input type=text id=OQsaveSearchTitle></label>";
  $buf .= "
<fieldset id=OQSaveReportEmailAlertOpts>
  <legend><label class=ckbox><input type=checkbox id=OQalertenabled> send email alert</label></legend>

  <p>
  <label>when records are:</label>
  <label><input type=checkbox name=OQalert_mask value=1 checked> added</label>
  <label><input type=checkbox name=OQalert_mask value=2> removed</label>
  <label><input type=checkbox name=OQalert_mask value=4> present</label>
    
  <p>
  <label>check every: <input type=text id=OQalert_interval_hour value=3 size=3 maxlength=4> hours</label></label>

  <p>
  <label title='Specify which days to send the alert.'>on days:</label>
  <label class=ckbox title=Sunday><input type=checkbox class=OQalert_dow value=0>S</label>
  <label class=ckbox title=Monday><input type=checkbox class=OQalert_dow value=1 checked>M</label>
  <label class=ckbox title=Tuesday><input type=checkbox class=OQalert_dow value=2 checked>T</label>
  <label class=ckbox title=Wednesday><input type=checkbox class=OQalert_dow value=3 checked>W</label>
  <label class=ckbox title=Thursday><input type=checkbox class=OQalert_dow value=4 checked>T</label>
  <label class=ckbox title=Friday><input type=checkbox class=OQalert_dow value=5 checked>F</label>
  <label class=ckbox title=Saturday><input type=checkbox class=OQalert_dow value=6>S</label>

  <p>
  <label title='Specify start hour to sent an alert.'>from: <input type=text value='8AM' size=4 maxlength=4 id=OQalert_start_hour placeholder=8AM></label> <label>to: <input type=text value='5PM' size=4 maxlength=4 id=OQalert_end_hour placeholder=5PM></label>
  <p><strong>Notice:</strong> This tool sends automatic alerts over insecure email. By creating an alert you acknowledge that the fields in the report will never be used to store sensitive data.</strong>
</fieldset>" if $$o{schema}{savedSearchAlerts};
  $buf .= "<p><button type=button class=OQSaveReportBut>save</button>";
  return $buf;
}

sub activate {
  my ($o) = @_;
  $$o{schema}{tools}{savereport} ||= {
    title => "Save Report",
    on_init => \&on_init,
    on_open => \&on_open
  };
}


# this function is called from a cron to help execute saved searches that have alerts that need to be checked
our $current_saved_search;
sub custom_output_handler {
  my ($o) = @_;

  my %opts;
  if (exists $$o{schema}{options}{__PACKAGE__}) {
    %opts = %{$$o{schema}{options}{__PACKAGE__}};
  } elsif (exists $$o{schema}{options}{'CGI::OptimalQuery::InteractiveQuery'}) {
    %opts = %{$$o{schema}{options}{'CGI::OptimalQuery::InteractiveQuery'}};
  }
  my %noEsc = map { $_ => 1 } @{ $opts{noEscapeCol} };


  # fetch all records in the report
  # update the uids hash
  # $$current_saved_search{uids}{<U_ID>} => 1-deleted, 2-seen before, 3-first time seen
  # Before this block all values for previously seen uids are 1
  # if the uid was previously seen and then seen again, we'll mark it with a 2
  # if it was not previously seen, and we see it now, we'll mark it with a 3
  # at the end of processing all previously found uids that weren't seen will still be marked 1
  # which indicates the record is no longer within the report
  my $cnt = 0;
  my $dataTruc = 0;
  my $row_cnt = 0;
  my $buf;
  { my $filter = $o->get_filter();
    $buf .= "<p><strong>Query: </strong>"
      .escapeHTML($$o{queryDescr}) if $$o{queryDescr};
    $buf .= "<p><strong>Filter: </strong>"
      .escapeHTML($filter) if $filter;
    $buf .= "<p><table class=OQdata><thead><tr><td></td>";
    foreach my $colAlias (@{ $o->get_usersel_cols }) {
      my $colOpts = $$o{schema}{select}{$colAlias}[3];
      $buf .= "<td>".escapeHTML($o->get_nice_name($colAlias))."</td>";
    }
    $buf .= "</tr></thead><tbody>";
  }

  while (my $rec = $o->{sth}->fetchrow_hashref()) {
    print STDERR "got row: ".Dumper($rec)."\n";

    die "MAX_ROWS_EXCEEDED - your report contains too many rows to send alerts via email. Reduce the total row count of your report by adding additional filters." if ++$cnt > $MAX_ROWS;
    $opts{mutateRecord}->($rec) if ref($opts{mutateRecord}) eq 'CODE';

    # if this record has been seen before, mark it with a '2'
    if (exists $$current_saved_search{uids}{$$rec{U_ID}}) {
      $$current_saved_search{uids}{$$rec{U_ID}}=2; 
print STDERR "setting: $$rec{U_ID}=>2\n";
    }

    # if this record hasn't been seen before, mark it with a '3'
    else {
      $$current_saved_search{uids}{$$rec{U_ID}}=3; 
print STDERR "setting: $$rec{U_ID}=>3\n";
    }

    # if we need to output report
    if (! $$current_saved_search{is_initial_run} && ! $dataTruc && (
             # output if when rows are present is checked
             ($$current_saved_search{ALERT_MASK} & 4)
             # output if when rows are added is checked AND this is a new row not seen before
          || ($$current_saved_search{ALERT_MASK} & 1 && $$current_saved_search{uids}{$$rec{U_ID}}==3))) {

      $row_cnt++;

      # get open record link
      my $link;
      if (ref($opts{OQdataLCol}) eq 'CODE') {
        $link = $opts{OQdataLCol}->($rec);
        if ($link =~ /href\s*\=\s*\"?\'?([^\s\'\"\>]+)/i) {
          $link = $1; 
        }
      } elsif (ref($opts{buildEditLink}) eq 'CODE') {
        $link = $opts{buildEditLink}->($o, $rec, \%opts);
      } elsif ($opts{editLink} ne '' && $$rec{U_ID} ne '') {
        $link = $opts{editLink}.(($opts{editLink} =~ /\?/)?'&':'?')."act=load&id=$$rec{U_ID}";
      }
      $buf .= "<tr";

      # if this record is first time visible
      $buf .= " class=ftv" if $$current_saved_search{uids}{$$rec{U_ID}}==3;
      $buf .= "><td>";
      if ($link) {
        $link = $$current_saved_search{opts}{base_url}.'/'.$link
          if $link !~ /^https?\:\/\//i;
        $buf .= "<a href='".escapeHTML($link)."'>open</a>";
      }
      $buf .= "</td>";
      foreach my $col (@{ $o->get_usersel_cols }) {
        my $val;
        if (exists $noEsc{$col}) {
          if (ref($$rec{$col}) eq 'ARRAY') {
            $val = join(' ', @{ $$rec{$col} });  
          } else {
            $val = $$rec{$col};
          }
        } elsif (ref($$rec{$col}) eq 'ARRAY') {
          $val = join(', ', map { escapeHTML($_) } @{ $$rec{$col} }); 
        } else {
          $val = escapeHTML($$rec{$col});
        }
        $buf .= "<td>$val</td>";
      }
      $buf .= "</tr>\n";

      $dataTruc = 1 if length($buf) > $TRUNC_REPORT_CHAR_LIMIT;
    }
  }
  $o->{sth}->finish();

  # if we found rows, encase it in a table with thead
  if ($row_cnt > 0) {
    $buf .= "</tbody></table>";
    $buf .= "<p><strong>This report does not show all data found because the report exceeds the maximum limit. Reduce report size by hiding columns, adding additional filters, or only showing new records.</strong>" if $dataTruc;
    $$current_saved_search{buf} = $buf;
  }

print STDERR "UIDS: ".Dumper($$current_saved_search{uids});
  return undef;
}

sub execute_saved_search_alerts {
  my %opts = @_;

  if ($opts{base_url} =~ /^(https?\:\/\/[^\/]+)(.*)/i) {
    $opts{server_url} = $1;
    $opts{path_prefix} = $2;
  } else {
    die "invalid option base_url";
  }
  die "missing option handler" unless ref($opts{handler}) eq 'CODE';
  my $dbh = $opts{dbh} or die "missing dbh";
  $opts{error_handler} ||= sub { print STDERR join(' ', @_)."\n"; };

  $opts{error_handler}->("execute_saved_search_alerts started") if $opts{debug};

  local $CGI::OptimalQuery::CustomOutput::custom_output_handler = \&custom_output_handler;

  my @dt = localtime;
  my $dow = $dt[6];
  my $hour = $dt[2];

  if ($$dbh{Driver}{Name} eq 'Oracle') {
    $$dbh{LongReadLen} = 900000;
    my ($readLen) = $dbh->selectrow_array("
      SELECT GREATEST(
        dbms_lob.getlength(params),
        dbms_lob.getlength(alert_uids)
      )
      FROM oq_saved_search");
    $$dbh{LongReadLen} = $readLen if $readLen > $$dbh{LongReadLen};
  }

  # find all saved searches that need to be checked
  my @recs;
  { local $$dbh{FetchHashKeyName} = 'NAME_uc';

    my $sth = $dbh->prepare("
      SELECT *
      FROM oq_saved_search
      WHERE alert_uids = '##NOTPOPULATED##'
      OR (  alert_dow LIKE ?
        AND ? BETWEEN alert_start_hour AND alert_end_hour
        AND 

( 1=1 OR

(strftime('%s','now') - strftime('%s',COALESCE(alert_last_dt,'2000-01-01'))) > alert_interval_min
)
      )
      ORDER BY id");
    
    my @binds = ('%'.$dow.'%', $hour);
    $opts{error_handler}->("search for saved searches that need checked. BINDS: ".join(',', @binds)) if $opts{debug};
    $sth->execute(@binds);
    while (my $h = $sth->fetchrow_hashref()) { push @recs, $h; }
  }

  $opts{error_handler}->("found ".scalar(@recs)." saved searches to execute") if $opts{debug};

  # for each saved search that has alerts which need to be checked
  while ($#recs > -1) {
    my $rec = pop @recs;

    local $current_saved_search = $rec;
    my %uids = map { $_ => 1 } split /\~/, $$rec{ALERT_UIDS};
    $$rec{opts} = \%opts;
    $$rec{uids} = \%uids; # contains all the previously seen uids
    $$rec{buf} = ''; # will be populated with a table containing report rows for a simple HTML email
    $$rec{err_msg} = '';
    $$rec{is_initial_run} = 1 if $$rec{ALERT_UIDS} eq '##NOTPOPULATED##';
    $opts{error_handler}->("executing saved search: ".Dumper($rec)) if $opts{debug};

    # create CGI query
    my $p = eval '{'.$$rec{PARAMS}.'}'; 
    $p = {} unless ref($p) eq 'HASH';
    $$p{module} = 'CustomOutput'; # this will call our custom_output_handler function
    $$p{page} = 1;
    $$p{rows_page} = $MAX_ROWS + 1; # one more to detect overflow
    $CGI::OptimalQuery::q = new CGI($p);
    $opts{error_handler}->("setting CGI params ".Dumper($p)) if $opts{debug};

    my @update_uids;

    eval {
      # call app specific request bootstrap handler
      # which will execute a CGI::OptimalQuery object somehow
      # and populate $$rec{buf}, $$rec{uids}, $$rec{err_msg}
      $opts{handler}->($rec);
      $opts{error_handler}->("after OQ execution uids: ".Dumper(\%uids)) if $opts{debug};

      my $total_new = 0;
      my $total_deleted = 0;
      my $total_count = 0;
      while (my ($uid, $status) = each %uids) {
        if ($status == 1) {
          $total_deleted++;
        }
        else {
          push @update_uids, $uid;
          $total_count++;
          if ($status == 3) {
            $total_new++;
          }
        }
      }
      $opts{error_handler}->("total_new: $total_new; total_deleted: $total_deleted; total_count: $total_count") if $opts{debug};

      my $should_send_email = 1 if
        ! $$rec{is_initial_run} &&
        ( # alert when records are added
          ($$rec{ALERT_MASK} & 1 && $total_new > 0) ||
          # alert when records are deleted
          ($$rec{ALERT_MASK} & 2 && $total_deleted > 0) ||
          # alert when records are present
          ($$rec{ALERT_MASK} & 4 && $total_count > 0)
        );

      if ($should_send_email) {
        my %email = (
          to => $$rec{EMAIL},
          subject => $$rec{OQ_TITLE},
          from => $$rec{EMAIL_FROM} || ($ENV{USER}||'root').'@'.($ENV{HOSTNAME}||'localhost'),
          'Reply-To' => $$rec{REPLY_TO} || $$rec{EMAIL},
          'content-type' => 'text/html; charset="iso-8859-1"'
        );
        $email{subject} .= " ($total_new added)" if $total_new > 0; 

        $email{body} = 
"<html>
<head>
<title>".escapeHTML($$rec{OQ_TITLE})."</title>
<style>
.OQSSAlert * {
  font-family: sans-serif;
}
.OQSSAlert h2 {
  margin: 0;
  font-size: 14px;
}
.OQSSAlert table {
  border-collapse: collapse;
}
.OQSSAlert thead td {
  font-weight: bold;
  color: white;
  background-color: #999;
}
.OQSSAlert td {
  padding: 4px;
  border: 1px solid #aaa;
  font-size: 11px;
}
.OQSSAlert .ftv {
  background-color: #E2FFE2;
}
.OQSSAlert p {
  margin: .5em 0;
}
.OQSSAlert .ib {
  display: inline-block;
  margin-left: 6px;
  padding: 6px;
}
</style>
</head>
<body>
<div class=OQSSAlert>
<h2>".escapeHTML($$rec{OQ_TITLE})."</h2>
<p>
$$rec{buf}
<p>
<span class=ib>total: $total_count</span>
<span class='ftv ib'>added: $total_new</span>
<span class=ib>removed: $total_deleted</span>
<p>
<a href='".escapeHTML("$opts{server_url}$$rec{URI}?OQLoadSavedSearch=$$rec{ID}")."'>current data</a> | <a href=/todo>notification settings</a>
</div>
</body>
</html>";

        $opts{error_handler}->("email: ".Dumper(\%email)) if $opts{debug};
        Mail::Sendmail::sendmail(%email) or die "could not send email to: $$rec{EMAIL}";
      }
    };
    if ($@) {
      $opts{error_handler}->("Error: $@");
      $$rec{err_msg} = $@;
      my %email = (
        to => $$rec{EMAIL},
        subject => "Problem with alert: $$rec{OQ_TITLE}",
        from => $$rec{EMAIL_FROM} || ($ENV{USER}||'root').'@'.($ENV{HOSTNAME}||'localhost'),
        'Reply-To' => $$rec{REPLY_TO} || $$rec{EMAIL},
        body => "Your saved search alert encountered the following error:\n\n$$rec{err_msg}\n\nPlease contact your administrator if you are unable to fix the problem."
      );
      Mail::Sendmail::sendmail(%email);
    }

    # update database
    my $update_uids = join('~', sort @update_uids);
    $update_uids = undef if $update_uids eq '';
    $$rec{err_msg} = undef if $$rec{err_msg} eq '';
    my @binds = ($$rec{err_msg});
    my $sql = "UPDATE oq_saved_search SET alert_last_dt=DATETIME(), alert_err=?";
    if ($update_uids ne $$rec{ALERT_UIDS}) {
      $sql .= ", alert_uids=?";
      push @binds, $update_uids;
    }
    $sql .= " WHERE id=?";
    push @binds, $$rec{ID};
    $opts{error_handler}->("SQL: $sql\nBINDS: ".join(',', @binds)) if $opts{debug};
    my $sth = $dbh->prepare_cached($sql);
    $sth->execute(@binds);
  }

  $opts{error_handler}->("execute_saved_search_alerts done") if $opts{debug};
}


1;
