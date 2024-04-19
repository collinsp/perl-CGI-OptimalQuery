package CGI::OptimalQuery::InteractiveQuery2;

use strict;
use warnings;
no warnings qw( uninitialized );
use base 'CGI::OptimalQuery::Base';
use CGI();

sub escapeHTML { CGI::OptimalQuery::Base::escapeHTML(@_) }

sub output {
  my $o = shift;

  my %opts = %{ $o->get_opts() };
  
  # evalulate code refs
  for (qw(httpHeader htmlFooter htmlHeader OQdocTop
          OQdocBottom OQformTop OQformBottom )) {
    $opts{$_} = $opts{$_}->($o) if ref($opts{$_}) eq 'CODE';
  }

  # define defaults
  $opts{OQdocTop}       ||= '';
  $opts{OQdocBottom}    ||= '';
  $opts{OQformTop}      ||= '';
  $opts{OQformBottom}   ||= '';
  $opts{editButtonLabel}||= 'open';
  $opts{disable_sort}   ||= 0;
  $opts{disable_filter} ||= 0;
  $opts{disable_select} ||= 0;
  $opts{mutateRecord}   ||= undef;
  $opts{editLink}       ||= undef;
  $opts{htmlExtraHead}  ||= "";
  if (! exists $opts{usePopups}) {
    $opts{usePopups}=1;
  } else {
    $opts{usePopups}=($opts{usePopups}) ? 1 : 0;
  }
  if (! exists $opts{useAjax}) {
    $opts{useAjax} = $opts{usePopups};
  } else {
    $opts{useAjax}=($opts{useAjax}) ? 1 : 0;
  }

  $opts{httpHeader} = $$o{httpHeader}->(-type=>'text/html',-expires=>'now')
    unless exists $opts{httpHeader};
  $opts{htmlFooter} = "</body>\n</html>\n"
    unless exists $opts{htmlFooter};

  my $newBut;
  if ($opts{NewButton}) {
    $newBut = (ref($opts{NewButton}) eq 'CODE') ? $opts{NewButton}->($o, \%opts) : $opts{NewButton};
  }
  elsif (ref($opts{buildNewLink}) eq 'CODE') {
    my $link = $opts{buildNewLink}->($o, \%opts);
    if ($link ne '') {
      $newBut = "<button type=button class=OQnewBut";
      $newBut .= " data-target=_blank" if $opts{usePopups};
      $newBut .= " data-href='".escapeHTML($link)."'>new</button>";
    }
  }
  elsif (exists $opts{buildNewLink} && $opts{buildNewLink} eq '') {}
  elsif ($opts{editLink} ne '') {
    my $link = $opts{editLink}.(($opts{editLink} =~ /\?/)?'&':'?')."on_update=OQrefresh&act=new";
    if ($link ne '') {
      $newBut = "<button type=button class=OQnewBut";
      $newBut .= " data-target=_blank" if $opts{usePopups};
      $newBut .= " data-href='".escapeHTML($link)."'>new</button>";
    }
  }

  my $ver = "ver=$CGI::OptimalQuery::VERSION-1";   # note minor changes so added "-1" because CGI::OptimalQuery::VERSION did not change
  my $buf;
  my $script;
  $script .= "window.OQWindowHeight=$opts{WindowHeight};\n" if $opts{WindowHeight};
  $script .= "window.OQWindowWidth=$opts{WindowWidth};\n" if $opts{WindowWidth};
  $script .= "window.OQuseAjax=$opts{useAjax};\n";
  $script .= "window.OQusePopups=$opts{usePopups};\n";

  if (! exists $opts{htmlHeader}) {
    $opts{htmlHeader} =
"<!DOCTYPE html>
<html>
<head>
<title>".escapeHTML($o->get_title)."</title>
<link id=OQIQ2CSS rel=stylesheet type=text/css href='$$o{schema}{resourceURI}/InteractiveQuery2.css?$ver'>
<meta name=viewport content='width=device-width, initial-scale=1.0, user-scalable=no'>  
".$opts{htmlExtraHead}."</head>
<body id=OQbody>";
  } else {
      $script .= "
  if (! document.getElementById('OQIQ2CSS')) {
    var a = document.createElement('link');
    a.setAttribute('rel','stylesheet');
    a.setAttribute('type','text/css');
    a.setAttribute('id','OQIQ2CSS');
    a.setAttribute('href','$$o{schema}{resourceURI}/InteractiveQuery2.css?1');
    document.getElementsByTagName('head')[0].appendChild(a);
  }\n";
  }

  if ($opts{color}) {
    $script .= "
  var d = document.createElement('style');
  var r = document.createTextNode('.OQhead { background-color: $opts{color}; }');
  d.type = 'text/css';
  if (d.styleSheet)
    d.styleSheet.cssText = r.nodeValue;
  else d.appendChild(r);
  document.getElementsByTagName('head')[0].appendChild(d);\n";
  }

  $buf = $opts{httpHeader}.$opts{htmlHeader};
  $buf .= "<script src=$$o{schema}{resourceURI}/jquery.js?$ver></script>" unless $opts{jquery_already_sent};

  $script .= $opts{OQscript};

  $buf .= "
<script src=$$o{schema}{resourceURI}/InteractiveQuery2.js?$ver></script>
<script>
(function(){
$script
})();
</script>";
  $buf .= "
<div class=OQdoc>
<div class=OQdocTop>$opts{OQdocTop}</div>";

  # ouput tools panel
  my @tools = sort keys %{$$o{schema}{tools}};
  if ($#tools > -1) {
    $buf .= "<div class=OQToolsPanel-pos-div><div class=OQToolsPanel-align-div><div class=OQToolsPanel>";
    foreach my $key (sort keys %{$$o{schema}{tools}}) {
      my $tool = $$o{schema}{tools}{$key};
      my $toolContent = '';
      $buf .= "<details data-toolkey=$key class=OQToolExpander><summary>".escapeHTML($$tool{title})."</summary>$toolContent</details>";
    }
    $buf .= "<button class=OQToolsCancelBut type=button>&#10005;</button></div></div></div>";
  }

  $buf .= "
<form class='OQform oqmode-$$o{oqmode}' name=OQform action='".escapeHTML($$o{schema}{URI_standalone}||$$o{schema}{URI})."' method=get>
<input type=hidden name=show value='".escapeHTML(join(',',@{$$o{show}}))."'>
<input type=hidden name=filter value='".escapeHTML($$o{filter})."'>
<input type=hidden name=hiddenFilter value='".escapeHTML($$o{hiddenFilter})."'>
<input type=hidden name=queryDescr value='".escapeHTML($$o{queryDescr})."'>
<input type=hidden name=sort value='".escapeHTML($$o{'sort'})."'>\n";
  $buf .= "<input type=hidden name=oqmode value='".escapeHTML($$o{oqmode})."'>\n" if $$o{oqmode};
  $buf .= "<input type=hidden name=module value='".escapeHTML($$o{module})."'>\n" if $$o{module};
  $buf .= $o->csrf_field();

  my @p = qw( OQss on_select on_update );
  push @p, @{ $$o{schema}{state_params} } if ref($$o{schema}{state_params}) eq 'ARRAY'; 
  foreach my $p (@p) {
    my $v = $$o{q}->param($p);
    $buf .= "<input type=hidden name='".escapeHTML($p)."' value='".escapeHTML($v)."'>\n" if $v ne '';
  }

  $buf .=
"<a name=OQtop></a>
<div class=OQformTop>$opts{OQformTop}</div>

<div class=OQhead>
<div class=OQtitle>".escapeHTML($o->get_title)."</div>";

  my $cnt = $o->get_count();
  if ($cnt==0) {
    $buf .= "<div class=OQsummary>(0) results</div>";
  }
  elsif ($cnt == 1) {
    $buf .= "<div class=OQsummary>($cnt) result</div>";
  } else {
    $buf .= "<div class=OQsummary>(".$o->commify($o->get_lo_rec)." - ".$o->commify($o->get_hi_rec).") of ".$o->commify($o->get_count)." results</div>";
  }

  $buf .= "
<div class=OQcmds>";
  $buf .= "
<button type=button class=OQFilterBut>filter</button>
<button type=button class=OQAddColumnsBut>add column</button>" if $$o{oqmode} eq 'recview';
  $buf .= "
$newBut
<button type=button class=OQrefreshBut>refresh</button>
<button type=button class=OQToolsBut>tools</button>
<button aria-label='toggle table/record report view' class=OQToggleTableViewBut>view</button>
</div>";

  $buf .= "
</div>";

  my $trs;
  $trs .= "<tr class=OQQueryDescr><td class=OQlabel>Query:</td><td>".escapeHTML($$o{queryDescr})."</td></tr>" if $$o{queryDescr};

  my $filter = $o->get_filter();
  if ($filter) {
    $trs .= "<tr";
    $trs .= " data-nofilter" if $opts{disable_filter};
    $trs .= "><td class=OQlabel>Filter:</td><td><a href=# class=OQFilterDescr title='click to edit filter'>".escapeHTML($filter)."</a></td></tr>";
  }

  my @sort = $o->sth->sort_descr;
  if ($#sort > -1) {
    $trs .= "<tr class=OQSortDescr><td class=OQlabel>Sort:</td><td>";
    my $comma = '';
    foreach my $c (@sort) {
      $trs .= $comma;
      $comma = ', ';
      $trs .= "<a title=remove tabindex=0 href=# class=OQRemoveSortBut title='remove sort field'>" unless $opts{disable_sort};
      $trs .= escapeHTML($c);
      $trs .= "</a>" unless $opts{disable_sort};
    }
    $trs .= "</tr>";
  }
  $buf .= "<table summary='report info' class=OQinfo";
  $buf .= " style='display:none;'" if ! $trs;
  $buf .= ">$trs</table>";

  # print update message
  my $updated_uid = $o->{q}->param('updated_uid');
  if ($updated_uid ne '') {
    my $msg;
    if (exists $opts{OQRecUpdateMsg}) {
      if (ref($opts{OQRecUpdateMsg}) eq 'CODE') {
        $msg = $opts{OQRecUpdateMsg}->($updated_uid);
      } else {
        $msg = $opts{OQRecUpdateMsg};
      }
    } elsif ($opts{editLink}) {
      my $editLink = $opts{editLink}.(($opts{editLink} =~ /\?/)?'&':'?')."on_update=OQrefresh&act=load&id=".CGI::escape($updated_uid);
      $msg = "Record <a class=opwin href='".escapeHTML($editLink)."'>".escapeHTML($updated_uid)."</a> updated.";
    }
    if ($msg) {
      $buf .= "<div class=OQRecUpdateMsg data-uid='".escapeHTML($updated_uid)."'>$msg</div>";
    }
  }

  $buf .= "<table class=OQdata>";

  my ($has_calc_row, $calc_row_html);

  if ($$o{oqmode} ne 'recview') {
    $buf .= "
<thead title='click to hide, sort, filter, or add columns'>
<tr>
<td class=OQdataLHead";

    if (! $$o{schema}{select}{U_ID} || (exists $opts{editLink} && ! $opts{editLink})) {
      $buf .= "></td>"
    } else {
      $buf .= " data-col=U_ID><a href=#>SYS ID</a></td>"
    }
  
    foreach my $colAlias (@{ $o->get_usersel_cols }) {
      $calc_row_html .= "<td>";
      my $colOpts = $$o{schema}{select}{$colAlias}[3];
      $buf .= "<td data-col='".escapeHTML($colAlias)."'";
      $buf .= " data-noselect" if $$colOpts{disable_select} || $opts{disable_select};
      $buf .= " data-nosort"   if $$colOpts{disable_sort}   || $opts{disable_sort};
      $buf .= " data-nofilter" if $$colOpts{disable_filter} || $opts{disable_filter};
      $buf .= " data-canUpdate" if $$o{oq}->canUpdate($colAlias);
      $buf .= "><a href=#>".escapeHTML($o->get_nice_name($colAlias))."</a>";
  
      my $calc_field_val = $o->get_calc_fields()->{$colAlias};
      $calc_field_val = 0 if $calc_field_val ne '' && $calc_field_val==0;  # format: 0.0000 => 0
      if ($calc_field_val ne '') {
        my $calc_title = $$colOpts{calc_title};
        if ($$colOpts{calc_sql} =~ /\bdistinct\b/i) {
          $calc_title = 'distinct';
        } elsif ($$colOpts{calc_sql} =~ /\bmin\b/i) {
          $calc_title = 'min';
        } elsif ($$colOpts{calc_sql} =~ /\bmax\b/i) {
          $calc_title = 'max';
        } else {
          $calc_title = 'total';
        } 
        $calc_row_html .= "<dl><dt>".escapeHTML($calc_title)."</dt><dd>".escapeHTML($calc_field_val)."</dd></dl>";
        $has_calc_row=1;
      }
      $calc_row_html .= "</td>";
      $buf .= "</td>";
    }
    $buf .= "
<td class=OQdataRHead></td>
</tr>
</thead>";
  }

  $buf .= "<tbody>\n";
  $buf .= "<tr class=OQcalcRow title='shows calculated values for all data in the report'><td></td>".$calc_row_html."<td></td></tr>" if $has_calc_row;

  my $recs_in_buffer = 0;
  my $typeMap = $o->{oq}->get_col_types('select');
  while (my $r = $o->fetch()) {
    my $leftBut;

    my $leftButLabel;
    if ($$r{U_ID} eq '') {
      $leftButLabel = $opts{editButtonLabel};
    } elsif ($$o{oqmode} eq 'recview') {
      $leftButLabel = 'open: '.$$r{U_ID}; 
    } else {
      $leftButLabel = $$r{U_ID}; 
    }

    if (ref($opts{OQdataLCol}) eq 'CODE') {
      $leftBut = $opts{OQdataLCol}->($r);
    } elsif (ref($opts{buildEditLink}) eq 'CODE') {
      my $link = $opts{buildEditLink}->($o, $r, \%opts);
      if ($link ne '') {
        $leftBut = "<a href='".escapeHTML($link)."' title='open record' class=OQeditBut>".escapeHTML($leftButLabel)."</a>";
      }
    } elsif ($$r{OQ_EDIT_LINK}) {
      $leftBut = "<a href='".escapeHTML($$r{OQ_EDIT_LINK})."' title='open record' class=OQeditBut>".escapeHTML($leftButLabel)."</a>";
    } elsif ($opts{editLink} ne '' && $$r{U_ID} ne '') {
      my $link = $opts{editLink}.(($opts{editLink} =~ /\?/)?'&':'?')."on_update=OQrefresh&act=load&id=$$r{U_ID}";
      $leftBut = "<a href='".escapeHTML($link)."' title='open record' class=OQeditBut>".escapeHTML($leftButLabel)."</a>";
    }

    my $rightBut;
    if (ref($opts{OQdataRCol}) eq 'CODE') {
      $rightBut = $opts{OQdataRCol}->($r);
    } elsif ($o->{q}->param('on_select') ne '') {
      my $on_select = $o->{q}->param('on_select');
      $on_select =~ s/\~.*//;
      my ($func,@argfields) = split /\,/, $on_select;
      $argfields[0] = 'U_ID' if $#argfields==-1;
      my @argvals = map {
        my $v=$$r{$_};
        $v = join(', ', @$v) if ref($v) eq 'ARRAY';
        $v =~ s/\~\~\~//g;
        $v;
      } @argfields;
      $rightBut = "<button type=button title='select record' class=OQselectBut data-rv='"
        .escapeHTML(join('~~~',@argvals))."'>select</button>";
    }


    $buf .= "<tr data-uid='".escapeHTML($$r{U_ID})."'";
    $buf .= " class=OQupdatedRow" if $updated_uid && $updated_uid eq $$r{U_ID};
    $buf .= ">";

    if ($$o{oqmode} eq 'recview') {
      $buf .= "<td>";
      foreach my $col (@{ $o->get_usersel_cols }) {
        my $val = $o->get_html_val($col);
        if ($val ne '') {
          my $label = $o->get_nice_name($col);
          $buf .= "<div class=OQrecviewLabel>".escapeHTML($label).":</div><div class=OQrecviewVal>$val</div>";
        }
      }
      $buf .= "$leftBut $rightBut</td>";
    }

    else {
      $buf .= "<td class=OQdataLCol>$leftBut</td>";
      foreach my $col (@{ $o->get_usersel_cols }) {
        my $val = $o->get_html_val($col);
        my $type = $$typeMap{$col} || 'char';
        $buf .= "<td";
        $buf .= " class=$type" unless $type eq 'char';
        $buf .= " nowrap" if $$o{schema}{select}{$col}[3]{nowrap};
        $buf .= " align='".escapeHTML($$o{schema}{select}{$col}[3]{align})."'"
          if $$o{schema}{select}{$col}[3]{align};
        $buf .= ">$val</td>";
      }
      $buf .= "<td class=OQdataRCol>$rightBut</td>";
    }

    $buf .= "</tr>\n";
    if (++$recs_in_buffer == 1000) {
      $$o{output_handler}->($buf);
      $buf = '';
      $recs_in_buffer = 0;
    }
  }
  $o->finish();

  $buf .= "</tbody></table>\n";

  my $numpages = $o->get_num_pages();

  $buf .= "<div class=OQPager>\n";
  if ($numpages != 1) {
    $buf .= "<button type=button title='previous page' class=OQPrevBut";
    $buf .= " disabled" if $$o{page}==1;
    $buf .= ">&lt;</button>";
  }
  $buf .= " <label>view <select name=rows_page>";
  foreach my $p (@{ $$o{schema}{results_per_page_picker_nums} }) {
    $buf .= "<option value=$p".(($p eq $$o{rows_page})?" selected":"").">$p";
  }
  $buf .= "</select> results per page</label>";
  if ($numpages != 1) {
    $buf .= " <label>Page <input type=number min=1 max=$numpages step=1 name=page value='"
.escapeHTML($$o{page})."'> of $numpages</label> <button type=button title='next page' class=OQNextBut>&gt;</button>"
  }
  $buf .= "
</div>
<div class=OQformBottom>$opts{OQformBottom}</div>
<div class=OQBlocker></div>
<div class=OQColumnCmdPanel>
  <button type=button class=OQUpdateDataToolBut title='update column values'>update</button>
  <button type=button class=OQLeftBut title='move column left'>move left</button>
  <button type=button class=OQRightBut title='move column right'>move right</button>
  <button type=button class=OQSortBut title='sort column A-Z'>sort</button>
  <button type=button class=OQReverseSortBut title='reverse sort column Z-A'>sort reverse</button>
  <button type=button class=OQFilterBut title='filter column'>filter</button>
  <button type=button class=OQAddColumnsBut title='add columns'>add column</button>
  <button type=button class=OQCloseBut title='hide column'>hide column</button>
</div>
</form>";

  $buf .= "<div class=OQdocBottom>$opts{OQdocBottom}</div>";
  $buf .= "</div>"; # div.OQdoc
  $buf .= $opts{htmlFooter};

  $$o{output_handler}->($buf);

  return undef;
}


1;
