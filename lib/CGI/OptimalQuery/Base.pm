package CGI::OptimalQuery::Base;

use strict;
use warnings;
no warnings qw( uninitialized redefine );

use CGI();
use Carp('confess');
use POSIX();
use DBIx::OptimalQuery;
use JSON::XS;
use Digest::SHA qw(sha256_base64 sha1_base64);

# some tools that OQ auto activates
use CGI::OptimalQuery::ExportDataTool();
use CGI::OptimalQuery::SaveSearchTool();
use CGI::OptimalQuery::LoadSearchTool();

sub escapeHTML {
  local ($_) = @_;
  s{&}{&amp;}gso;
  s{<}{&lt;}gso;
  s{>}{&gt;}gso;
  s{"}{&quot;}gso;
  s{'}{&#39;}gso;
  s{\x8b}{&#8249;}gso;
  s{\x9b}{&#8250;}gso;
  return $_;
}

sub can_embed { 0 }

# alias for output
sub print {
  my $o = shift;
  $o->output(@_);
}

sub new { 
  my $pack = shift;
  my $schema = shift;
  die "could not find schema!" unless ref($schema) eq 'HASH';

  my $o = bless {}, $pack;

  $$o{schema} = clone($schema);

  $$o{dbh} = $$o{schema}{dbh}
    or confess "couldn't find dbh in schema!";
  $$o{q} = $$o{schema}{q}
    or confess "couldn't find q in schema!";
  $$o{output_handler} = $$o{schema}{output_handler};
  $$o{error_handler} = $$o{schema}{error_handler};
  $$o{httpHeader} = $$o{schema}{httpHeader};
  
  # set defaults
  $$o{schema}{debug} ||= 0;
  $$o{schema}{check} = $ENV{'CGI-OPTIMALQUERY_CHECK'} 
    if ! defined $$o{schema}{check};
  $$o{schema}{check} = 0 if ! defined $$o{schema}{check};
  $$o{schema}{title} ||= "";
  $$o{schema}{options} ||= {};
  $$o{schema}{resourceURI} ||= $ENV{OPTIMALQUERY_RESOURCES} || '/OptimalQuery';
  $$o{schema}{savedSearchUserID} ||= undef;

  if (! $$o{schema}{URI}) {
    $_ = ($$o{q}->can('uri')) ? $$o{q}->uri() : $ENV{REQUEST_URI}; s/\?.*$//;
    $$o{schema}{URI} = $_;
    # disabled so we can run from command line for testing where REQUEST_URI probably isn't defined
    # or die "could not find 'URI' in schema"; 
  }
  $$o{schema}{URI_standalone} ||= $$o{schema}{URI};

  # make sure developer is not using illegal state_params
  if (ref($$o{schema}{state_params}) eq 'ARRAY') {
    foreach my $p (@{ $$o{schema}{state_params} }) {
      die "cannot use reserved state param name: act" if $p eq 'act';
      die "cannot use reserved state param name: module" if $p eq 'module';
      die "cannot use reserved state param name: view" if $p eq 'view';
    }
  }

  # install tools
  CGI::OptimalQuery::ExportDataTool::activate($o);
  CGI::OptimalQuery::LoadSearchTool::activate($o);
  CGI::OptimalQuery::SaveSearchTool::activate($o);

  # run on_init function for each enabled tool
  foreach my $v (values %{ $$o{schema}{tools} }) {
    $$v{on_init}->($o) if ref($$v{on_init}) eq 'CODE';
  }

  # initializes $$o{oq}
  $o->oq() if $$o{schema}{select} && $$o{schema}{joins};
  return $o;
}



sub oq {
  my ($o) = @_;

  return $$o{oq} if $$o{oq};

  # check for required attributes
  confess "specified select is not a hash ref!"
    unless ref $$o{schema}{select} eq "HASH";
  confess "specified joins is not a hash ref!"
    unless ref $$o{schema}{joins} eq "HASH";

  # is a query fully defined
  # construct optimal query object
  $$o{oq} = DBIx::OptimalQuery->new(
    'dbh'           => $$o{schema}{dbh},
    'select'        => $$o{schema}{select},
    'joins'         => $$o{schema}{joins},
    'named_filters' => $$o{schema}{named_filters},
    'named_sorts'   => $$o{schema}{named_sorts},
    'debug'         => $$o{schema}{debug},
    'error_handler' => $$o{schema}{error_handler}
  );

  # the following code is responsible for setting the disable_sort flag for all
  # multi valued selects (since it never makes since to sort a m-valued column)
  my %cached_dep_multival_status;
  my $find_dep_multival_status_i; 
  my $find_dep_multival_status;
  $find_dep_multival_status = sub {
    my $joinAlias = shift;
    $find_dep_multival_status_i++;
    die "could not resolve join alias: $joinAlias deps" if $find_dep_multival_status_i > 100;
    if (! exists $cached_dep_multival_status{$joinAlias}) {
      my $v;
      if (exists $$o{oq}{joins}{$joinAlias}[3]{new_cursor}) { $v = 0; }
      elsif (! @{ $$o{oq}{joins}{$joinAlias}[0] }) { $v = 1; }
      else { $v = $find_dep_multival_status->($$o{oq}{joins}{$joinAlias}[0][0]); }
      $cached_dep_multival_status{$joinAlias} = $v;
    }
    return $cached_dep_multival_status{$joinAlias};
  };

  # loop though all selects
  foreach my $selectAlias (keys %{ $$o{oq}{select} }) {
    $find_dep_multival_status_i = 0;

    # set the disable sort flag is select is a multi value
    $$o{oq}{select}{$selectAlias}[3]{disable_sort} = 1
      if ! $find_dep_multival_status->($$o{oq}{select}{$selectAlias}[0][0]);

    # set is_hidden flag if select does not have a nice name assigned
    $$o{oq}{select}{$selectAlias}[3]{is_hidden} = 1
      if ! $$o{oq}{select}{$selectAlias}[2];

    # if no SQL (could be a recview) then disable sort, filter
    if (! $$o{oq}{select}{$selectAlias}[1]) {
      $$o{oq}{select}{$selectAlias}[3]{disable_sort} = 1;
      $$o{oq}{select}{$selectAlias}[3]{disable_filter} = 1;
    }
  }

  # if any fields are passed into on_select, ensure they are always selected
  my $on_select = $$o{q}->param('on_select');
  if ($on_select =~ /[^\,]+\,(.+)/) {
    my @fields = split /\,/, $1;
    for (@fields) {
      $$o{oq}{'select'}{$_}[3]{always_select}=1
        if exists $$o{oq}{'select'}{$_};
    }
  }

  # check schema validity
  $$o{oq}->check_join_counts() if $$o{schema}{check} && ! defined $$o{q}->param('module');

  my $schemaparams = $$o{schema}{params} || {};
  foreach my $k (qw( page rows_page show filter hiddenFilter queryDescr sort oqmode )) { 
    if (exists $$schemaparams{$k}) {
      $$o{$k} = $$schemaparams{$k};
    } elsif (defined $$o{q}->param($k)) {
      $$o{$k} = $$o{q}->param($k);
    } else {
      $$o{$k} = $$o{schema}{$k};
    }
  }

  $$o{oqmode} ||= 'default';
  $$o{oqmode} =~ s/\W//g;

  $$o{schema}{results_per_page_picker_nums} ||= [25,50,100,500,1000,'All'];
  $$o{rows_page} ||= $$o{schema}{rows_page} || $$o{schema}{results_per_page_picker_nums}[0] || 10;
  $$o{page} ||= 1;

  # convert show into array
  if (! ref($$o{show})) {
    my @ar = split /\,/, $$o{show};
    $$o{show} = \@ar;
  } 

  # if we still don't have something to show then show all cols
  # that aren't hidden
  if (! scalar( @{ $$o{show} } )) {
    for (keys %{ $$o{schema}{select} }) {
      push @{$$o{show}}, $_ unless $$o{oq}->{'select'}->{$_}->[3]->{is_hidden};
    }
  }

  return $$o{oq};
}

# ----------- UTILITY METHODS ------------------------------------------------

sub escape_html  {  escapeHTML($_[1]) }
sub escape_uri   { CGI::escape($_[1]) }
sub escape_js    {
  my $o = shift;
  $_ = shift;
  s/\\/\\x5C/g;  #escape \
  s/\n/\\x0A/g;  #escape new lines
  s/\'/\\x27/g;  #escape '
  s/\"/\\x22/g;  #escape "
  s/\&/\\x26/g;  #escape &
  s/\r//g;       #remove carriage returns
  s/script/scr\\x69pt/ig; # make nice script tags
  return $_;
}
sub commify {
  my $o = shift;
  my $text = reverse $_[0];
  $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
  return scalar reverse $text;
} # Commify


my %no_clone = ('dbh' => 1, 'q' => 1);
sub clone {
  my $thing = shift;
  if (ref($thing) eq 'HASH') {
    my %tmp;
    while (my ($k,$v) = each %$thing) { 
      if (exists $no_clone{$k}) { $tmp{$k} = $v; }
      else { $tmp{$k} = clone($v); }
    }
    $thing = \%tmp;
  } elsif (ref($thing) eq 'ARRAY') {
    my @tmp;
    foreach my $v (@$thing) { push @tmp, clone($v); }
    $thing = \@tmp;
  } 
  return $thing;
}



#-------------- ACCESSORS --------------------------------------------------
sub sth {
  my ($o) = @_;
  return $$o{sth} if $$o{sth};

  # create & execute SQL statement
  $$o{sth} = $$o{oq}->prepare(
    show   => $$o{show},
    filter => $$o{filter},
    hiddenFilter => $$o{hiddenFilter},
    forceFilter => $$o{schema}{forceFilter},
    sort   => $$o{sort} );

  # current fetched row
  $$o{rec} = undef;

  # calculate what the limit is
  # and make sure page, num_pages, rows_page make sense
  if ($$o{sth}->count() == 0) {
    $$o{page} = 0;
    $$o{rows_page} = 0;
    $$o{num_pages} = 0;
    $$o{limit} = [0,0];
  } elsif ($$o{rows_page} eq 'All' || ($$o{sth}->count() < $$o{rows_page})) {
    $$o{rows_page} = "All";
    $$o{page} = 1;
    $$o{num_pages} = 1;
    $$o{limit} = [1, $$o{sth}->count()];
  } else {
    $$o{num_pages} = POSIX::ceil($$o{sth}->count() / $$o{rows_page});
    $$o{page} = $$o{num_pages} if $$o{page} > $$o{num_pages};
    my $lo = ($$o{rows_page} * $$o{page}) - $$o{rows_page} + 1;
    my $hi = $lo + $$o{rows_page} - 1;
    $hi = $$o{sth}->count() if $hi > $$o{sth}->count();
    $$o{limit} = [$lo, $hi];
  }

  $$o{sth}->set_limit($$o{limit});

  return $$o{sth};
}
sub get_count        { $_[0]->sth->count() }
sub get_calc_fields  { $_[0]->sth->fetch_calc_fields() }
sub get_rows_page    { $_[0]{rows_page} }
sub get_current_page { $_[0]{page}      }
sub get_lo_rec       { $_[0]->sth->get_lo_rec() }
sub get_hi_rec       { $_[0]->sth->get_hi_rec() }
sub get_num_pages    { $_[0]{num_pages} }
sub get_title        { $_[0]{schema}{title} }
sub get_filter       { $_[0]->sth->filter_descr() }
sub get_sort         { $_[0]->sth->sort_descr() }
sub get_query        { $_[0]{query}     }
sub get_nice_name    {
  my ($o, $colAlias) = @_;
  $$o{schema}{select}{$colAlias}[2] ||= join(' ', map { ucfirst } split /[\ \_]+/, $colAlias);
  return $$o{schema}{select}{$colAlias}[2];
}
sub get_num_usersel_cols { scalar @{$_[0]{show}} }
sub get_usersel_cols { $_[0]{show} }

sub finish {
  my ($o) = @_;
  $$o{sth}->finish() if $$o{sth};
  undef $$o{sth};
}

# get the options
sub get_opts {
  my ($o) = @_; 

  if (! $$o{_opts}) {
    my $class = ref $o;

    if (exists $$o{schema}{options}{$class}) {
      $$o{_opts} = $$o{schema}{options}{$class};
    }

    # remove numerics and try again, this allows for module developers to create upgraded modules that use
    # backwards compatible options example: InteractiveQuery & InteractiveQuery2
    elsif ($class =~ s/\d+$// && exists $$o{schema}{options}{$class}) {
      $$o{_opts} = $$o{schema}{options}{$class};
    }

    else { 
      $$o{_opts} = {};
    }
  }

  return $$o{_opts};
}

sub fetch {
  my ($o) = @_;
  if ($$o{rec} = $o->sth->fetchrow_hashref()) {
    my $mutator = $o->get_opts()->{'mutateRecord'};
    $mutator->($$o{rec}) if ref($mutator) eq 'CODE';
    $$o{schema}{mutateRecord}->($$o{rec}) if ref($$o{schema}{mutateRecord}) eq 'CODE';
    return $$o{rec};
  }
  return undef;
}

sub get_val {
  my ($o, $colAlias) = @_;
  $o->fetch() unless $$o{rec};
  my $formatter = $$o{schema}{select}{$colAlias}[3]{formatter} || \&default_formatter;
  return $formatter->($$o{rec}{$colAlias}, $$o{rec}, $o, $colAlias);
}

sub get_html_val {
  my ($o, $colAlias) = @_;
  $o->fetch() unless $$o{rec};
  my $rv;
  my @args = ($$o{rec}{$colAlias}, $$o{rec}, $o, $colAlias);
  if ($$o{schema}{select}{$colAlias}[3]{html_formatter}) {
    $rv = $$o{schema}{select}{$colAlias}[3]{html_formatter}->(@args);
  } elsif ($$o{schema}{select}{$colAlias}[3]{formatter}) {
    $rv = escapeHTML($$o{schema}{select}{$colAlias}[3]{formatter}->(@args));
  } else {
    $rv = default_html_formatter(@args);
  }
  return $rv;
}

sub default_formatter {
  my ($val) = @_;
  return (ref($val) eq 'ARRAY') ? join(', ', @$val) : $val;
}

sub default_html_formatter {
  my ($val, $rec, $o, $colAlias) = @_;
  if (! exists $$o{_noEscapeColMap}) {
    my %noEsc = map { $_ => 1 } @{ $o->get_opts()->{'noEscapeCol'} || [] };
    $$o{_noEscapeColMap} = \%noEsc;
  }
  if ($$o{_noEscapeColMap}{$colAlias}) {
    $val = join(' ', @$val) if ref($val) eq 'ARRAY';
  } elsif (ref($val) eq 'ARRAY') {
    $val = join(', ', map { escapeHTML($_) } @$val);
  } else {
    $val = escapeHTML($val);
  }
  return $val;
}

sub recview_formatter {
  my ($val, $rec, $o, $colAlias) = @_;

  my @val;
  foreach my $colAlias2 (@{ $$o{schema}{select}{$colAlias}[3]{select} }) {
    my $val2 = $o->get_val($colAlias2);
    if ($val2 ne '') {
      my $label = $$o{schema}{select}{$colAlias2}[2] || $colAlias2;
      push @val, "$label: $val2";
    }
  }
  return join("\n", @val);
}

sub recview_html_formatter {
  my ($val, $rec, $o, $colAlias) = @_;

  my @val;
  foreach my $colAlias2 (@{ $$o{schema}{select}{$colAlias}[3]{select} }) {
    my $val2 = $o->get_html_val($colAlias2);
    if ($val2 ne '') {
      my $label = $$o{schema}{select}{$colAlias2}[2] || $colAlias2;
      push @val, "<tr><td>".escapeHTML($label)."</td><td>$val2</td></tr>";
    }
  }
  return $#val > -1 ? "<table class=OQrecview>".join('', @val)."</table>" : '';
}

sub get_link {
  my ($o) = @_;
  my @args;
  foreach my $k (qw( show filter hiddenFilter queryDescr sort)) {
    my $v1 = $$o{$k};
    $v1 = join(',', @$v1) if ref($v1) eq 'ARRAY';
    my $v2 = $$o{schema}{$k};
    $v2 = join(',', @$v2) if ref($v2) eq 'ARRAY';
    push @args, "$k=".CGI::escape($v1) if $v1 ne $v2;
  }
  my $rv = $$o{schema}{URI};
  my $args = join('&', @args);
  $rv .= '?'.$args if $args;
  return $rv;
}

sub csrf_field {
  my ($o, @do_not_tamper_params) = @_;
  return "<input type=hidden name=_oqcsrf value='".$o->csrf_token(@_)."'>";
}

sub csrf_token {
  my ($o, @do_not_tamper_params) = @_;
  my @do_not_tamper_vals = map { join('|', $$o{q}->param($_)) } @do_not_tamper_params;
  return $o->csrf_token_vals(@do_not_tamper_vals);
}

sub csrf_token_vals {
  my ($o, @do_not_tamper_vals) = @_;

  my $salt = sha1_base64(rand().$$.rand());
  $salt =~ s/\W//g;
  $salt = substr($salt, 0, 5);
  die "invalid salt length\n" if length($salt) != 5;

  my @tokens = ($$o{schema}{server_secret},$salt,$$o{schema}{savedSearchUserID},@do_not_tamper_vals);
  my $cksum = sha256_base64(@tokens); $cksum =~ s/\W//g;
  my $csrf = $cksum.$salt;

#$$o{schema}{error_handler}->("generated csrf: $csrf   tokens: ".join(',',@tokens));
  return $csrf;
}

sub csrf_check {
  my ($o, @do_not_tamper_params) = @_;

  my $csrf = $$o{q}->param('_oqcsrf') || $$o{q}->url_param('_oqcsrf') || $ENV{'HTTP_X_CSRFTOKEN'};
  die "BAD_CSRF - invalid param\n" unless $csrf;

  if ($$o{schema}{server_secret} eq '') {
    $$o{schema}{error_handler}->("WARNING: optimal query schema is missing 'server_secret' which protects against CSRF attacks");
  }

  my $cksum0 = $csrf;
  my ($cksum1, $salt, @tokens);
  if ($cksum0 =~ s/(.{5})$//) {
    my $salt = $1;
    @tokens = ($$o{schema}{server_secret},$salt,$$o{schema}{savedSearchUserID},map { join('|', $$o{q}->param($_)) } @do_not_tamper_params);
    $cksum1 = sha256_base64(@tokens); $cksum1 =~ s/\W//g;
  }
  if ($cksum0 ne $cksum1) {
#$$o{schema}{error_handler}->("failed csrf_check; csrf: $csrf   cksum: $cksum0 != $cksum1   tokens: ".join(',', @tokens));
    die "BAD_CSRF - Sorry this page has expired. Please reload and try again.\n";
  }
  return undef;
}

# returns list of available saved searches for this user
sub get_saved_searches {
  my ($o, %opts) = @_;
  return () unless $$o{schema}{savedSearchUserID};

  local $$o{dbh}{FetchHashKeyName} = 'NAME_uc';
  my $oracleReadLen;

  my @binds;
  my $sql= "SELECT id,user_title,uri,is_default,oq_title";

  # for old confgs that do not have a URI_utils config, select params field
  # which will be used to extract state params
  if (! $$o{schema}{URI_utils}) {
    $sql .= ",params";
  
    # if oracle is being used, make sure params longreadlen is extended if neccessary
    if ($$o{dbh}{Driver}{Name} eq 'Oracle') {
      ($oracleReadLen) = $$o{dbh}->selectrow_array("SELECT MAX(dbms_lob.getlength(params)) FROM oq_saved_search WHERE user_id=?", undef, $$o{schema}{savedSearchUserID});
    }
  }

  $sql .= " FROM oq_saved_search WHERE user_id=?";
  push @binds, $$o{schema}{savedSearchUserID};

  if ($opts{uri}) {
    $sql .= " AND uri=?";
    push @binds, $opts{uri};
  }
  if ($opts{oq_title}) {
    $sql .= " AND oq_title=?";
    push @binds, $opts{oq_title};
  }

  $sql .= " ORDER BY oq_title, user_title";

  local $$o{dbh}->{LongReadLen} = $oracleReadLen
    if $oracleReadLen && $oracleReadLen > $$o{dbh}->{LongReadLen};
  my $sth = $$o{dbh}->prepare($sql);
  $sth->execute(@binds);

  my $csrf_token = $o->csrf_token();

  my @rv;
  while (my $h = $sth->fetchrow_hashref()) {
    my $url = $$o{schema}{URI_utils} || $$h{URI};
    $$h{LOAD_URL}   = $url.'?OQLoadSavedSearch='.$$h{ID};
    $$h{DELETE_URL} = $url.'?OQDeleteSavedSearch='.$$h{ID}.'&_oqcsrf='.$o->escape_uri($csrf_token);

    # if URI_utils config is missing, we must use the report URI
    # must extract state params since they may be neccessary to load report
    # this is ugly but neccessary for old style configs!
    if ($$h{PARAMS}) {
      my $params = eval '{'.$$h{PARAMS}.'}';
      my $args='';
      foreach my $k (sort keys %$params) {
        next if $k =~ /^(module|show|rows_page|page|hiddenFilter|filter|queryDescr|sort)$/;
        my $v = $$params{$k};
        if (ref($v) eq 'ARRAY') {
          $args .= '&'.$k.'='.$o->escape_uri($_) for @$v;
        } else {
          $args .= '&'.$k.'='.$o->escape_uri($v);
        }
      }
      $$h{LOAD_URL} .= $args; 
      $$h{DELETE_URL} .= $args; 
    }

    push @rv, $h;
  }

  return @rv;
}

# returns saved searches for this user
sub get_saved_searches_html {
  my ($o, %opts) = @_;
  my @saved_searches = $o->get_saved_searches(%opts);
  my $last_oq_title = '';
  my $buf = '';
  foreach my $h (@saved_searches) {
    if ($last_oq_title ne $$h{OQ_TITLE}) {
      $buf .= '</table>' if $last_oq_title;
      $last_oq_title = $$h{OQ_TITLE};
      $buf .= "<h4>".$o->escape_html($$h{OQ_TITLE})."</h4>" unless $opts{hide_title};
      $buf .= "<table>";
    }
    $buf .= "<tr><td><a href='".$o->escape_html($$h{LOAD_URL})."' title='load saved search' class=oqssload>".$o->escape_html($$h{USER_TITLE})."</a>";
    $buf .= " <em title='you set your saved search as the default view for all users who load this report; if deleted the system default will be used'>default</em>" if $$h{IS_DEFAULT};
    $buf .= "</td><td><button type=button title='delete saved search' class=oqssdelete data-url='".$o->escape_html($$h{DELETE_URL})."'>&#10005;</button></td></tr>";
  }
  $buf .= '</table>' if $last_oq_title;

  if ($buf) {
    $buf = '<div id=loadsavedsearches>'.$buf.'</div>
<script>
$("#loadsavedsearches").on("click", ".oqssdelete", function(e){
  e.preventDefault();
  var $t = $(this);
  var $tr = $t.closest("tr");
  $.ajax({
    type: "post",
    url: $t.attr("data-url"),
    success: function() {
      if ($tr.siblings().length==0) {
        var $table = $tr.closest("table");
        $table.prev("h4").add($table).remove();
      }
      else {
        $tr.remove();
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
