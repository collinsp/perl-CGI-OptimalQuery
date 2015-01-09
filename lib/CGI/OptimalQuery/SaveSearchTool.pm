package CGI::OptimalQuery::SaveSearchTool;

use strict;
use Data::Dumper;
use CGI();


my $TRUNC_REPORT_CHAR_LIMIT = 500000;   # ~ .5MB allowed per report

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
  <label>When Data is:
    <select id=OQalert_mask>
      <option value=1>added
      <option value=2>removed
      <option value=4>present
    </select>
  </label>

  <p>
  <label>Check Every: <input type=text id=OQalert_interval_hour value=3 size=3 maxlength=4> hours</label></label>

  <p>
  <label title='Specify which days to send the alert.'>On Days:</label>
  <label class=ckbox title=Sunday><input type=checkbox class=OQalert_dow value=7>S</label>
  <label class=ckbox title=Monday><input type=checkbox class=OQalert_dow value=1 checked>M</label>
  <label class=ckbox title=Tuesday><input type=checkbox class=OQalert_dow value=2 checked>T</label>
  <label class=ckbox title=Wednesday><input type=checkbox class=OQalert_dow value=3 checked>W</label>
  <label class=ckbox title=Thursday><input type=checkbox class=OQalert_dow value=4 checked>T</label>
  <label class=ckbox title=Friday><input type=checkbox class=OQalert_dow value=5 checked>F</label>
  <label class=ckbox title=Saturday><input type=checkbox class=OQalert_dow value=6>S</label>

  <p>
  <label title='Specify start hour to sent an alert.'>From: <input type=text value='8AM' size=4 maxlength=4 id=OQalert_start_hour placeholder=8AM></label> <label>To: <input type=text value='5PM' size=4 maxlength=4 id=OQalert_end_hour placeholder=5PM></label>
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


our $current_saved_search;
sub custom_output_handler {
  my ($o) = @_;

  my $buf;

  my %opts;
  if (exists $$o{schema}{options}{__PACKAGE__}) {
    %opts = %{$$o{schema}{options}{__PACKAGE__}};
  } elsif (exists $$o{schema}{options}{'CGI::OptimalQuery::InteractiveQuery'}) {
    %opts = %{$$o{schema}{options}{'CGI::OptimalQuery::InteractiveQuery'}};
  }

  # fetch all records in the report
  # update the uids hash
  # $$current_saved_search{uids}{<U_ID>} => 1-deleted, 2-seen before, 3-first time seen
  # Before this block all values for previously seen uids are 1
  # if the uid was previously seen and then seen again, we'll mark it with a 2
  # if it was not previously seen, and we see it now, we'll mark it with a 3
  # at the end of processing all previously found uids that weren't seen will still be marked 1
  # which indicates the record is no longer within the report
  while (my $rec = $o->{sth}->fetchrow_hashref()) {
    $opts{mutateRecord}->($r) if ref($opts{mutateRecord}) eq 'CODE';

    # if this record has been seen before, mark it with a '2'
    if (exists $$current_saved_search{uids}{$$rec{U_ID}}) {
      $$current_saved_search{uids}{$$rec{U_ID}}=2; 
    }

    # if this record hasn't been seen before, mark it with a '3'
    else {
      $$current_saved_search{uids}{$$rec{U_ID}}=3; 
    }

    # if we need to output report
    my $dataTruc = 0;
    if ($$current_saved_search{ALERT_MASK} & 5) {
      # get open record link
      my $link;
      if (ref($opts{OQdataLCol}) eq 'CODE') {
        $link = $opts{OQdataLCol}->($r);
        if ($link =~ /href\s*\=\s*\"?\'?([^\s\'\"\>]+)/i) {
          $link = $1; 
        }
      } elsif (ref($opts{buildEditLink}) eq 'CODE') {
        $link = $opts{buildEditLink}->($o, $r, \%opts);
      } elsif ($opts{editLink} ne '' && $$r{U_ID} ne '') {
        $link = $opts{editLink}.(($opts{editLink} =~ /\?/)?'&':'?')."act=load&id=$$r{U_ID}";
      }
      $buf .= "<tr><td>";
      $buf .= "<a href='".$link."'>open</a>" if $link;
      $buf .= "</td>";
      foreach my $col (@{ $o->get_usersel_cols }) {
        my $val;
        if (exists $noEsc{$col}) {
          if (ref($$r{$col}) eq 'ARRAY') {
            $val = join(' ', @{ $$r{$col} });  
          } else {
            $val = $$r{$col};
          }
        } elsif (ref($$r{$col}) eq 'ARRAY') {
          $val = join(', ', map { escape_html($_) } @{ $$r{$col} }); 
        } else {
          $val = escape_html($$r{$col});
        }
        $buf .= "<td>$val</td>";
      }
      $buf .= "</tr>";

      if (length($buf) > $TRUNC_REPORT_CHAR_LIMIT) {
        $dataTruc = 1;
        last;
      }
    }
    $o->{sth}->finish();

    # if we found rows, encase it in a table with thead
    if ($buf) {
      $buf = "<table class=OQdata><thead><tr><td></td>";
      foreach my $colAlias (@{ $o->get_usersel_cols }) {
        my $colOpts = $$o{schema}{select}{$colAlias}[3];
        $buf .= "<td>".escape_html($o->get_nice_name($colAlias))."</td>";
      }
      $buf .= "</tr></thead><tbody>$buf</tbody></table>";
      $buf .= "<p><strong>This report does not show all data found because the report exceeds the maximum limit. Reduce report size by including less columns or adding additional filters.</strong>" if $dataTruc;
    }
  }
  $$current_saved_search{buf} = $buf;
}

sub execute_saved_search_alerts {
  my %opts = @_;

  my %emails;

  local $CGI::OptimalQuery::CustomOutput::custom_output_handler = \&custom_output_handler;

  local $is_processing_saved_search_alerts = 1;

  die "missing handler CODEREF" unless ref($opts{handler}) eq 'CODE';
  my $dbh = $opts{dbh} or die "missing dbh";
  $opts{error_handler} ||= sub { print STDERR @_; };

  my @dt = localtime;
  my $dow = $dt[6] + 1;
  my $hour = $dt[5];

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
  my $sth = $dbh->prepare("
    SELECT *
    FROM oq_saved_search
    WHERE alert_dow LIKE ?
    AND alert_start_hour >= ?
    AND alert_end_hour <= ?
    AND alert_interval_min > (strftime('%s','now') - strftime('%s',COALESCE(alert_last_dt,'2000-01-01')))
    ORDER BY id");
  $sth->execute('%'.$dow.'%', $hour, $hour);
  my @recs;
  while (my $h = $sth->fetchrow_hashref()) { push @recs, $h; }

  foreach my $rec (@recs) {
    $current_saved_search = $rec;
    $p = eval '{'.$$rec{params}.'}'; 
    $p = {} unless ref($params) eq 'HASH';
    $$p{module} = 'CustomOuput';
    $$p{page} = 1; $$p{rows_page} = 'All';
    $$rec{q} = new CGI($p);
    my %uids = map { $_ => 1 } split /\~/, $$rec{ALERT_UIDS};
    $$rec{uids} = \%uids;

    # check to see if records were added
    if ($$rec{ALERT_MASK} & 1) {
    }
    # check to see if records were removed
    if ($$rec{ALERT_MASK} & 2) {
    }
    # check to see if records were present
    if ($$rec{ALERT_MASK} & 4) {
    }

    eval {
      $opts{handler}->($rec);
      if ($$rec{EMAIL}) {
        foreach my $uid (keys %uids) {
          if ($$rec{ALERT_MASK} & 1 && $uids{$uids} == 3) {
            my $editLink = 
            $emails{$$rec{EMAIL}}{$$rec{OQ_TITLE}}{added} .= "<a href={$uid};
          }
          elsif ($$rec{ALERT_MASK} & 2 && $uids{$uids} == 1) {
            $emails{$$rec{EMAIL}}{$$rec{OQ_TITLE}}{deleted}{$uid};
          }
          elsif ($$rec{ALERT_MASK} & 4 && $uids{$uids} > 1) {
            $emails{$$rec{EMAIL}}{$$rec{OQ_TITLE}}{present}{$uid};
          }
        }
      }
    };
    if ($@) {
    }

    # send emails
    foreach my $email (keys %emails) {
      foreach my $oq_title (
    }


  }
}


1;
