package CGI::OptimalQuery::Base;

use strict;
use warnings;
no warnings qw( uninitialized ); 
use CGI();
use Carp('confess');
use POSIX();
use DBIx::OptimalQuery;
use JSON::XS;

# some tools that OQ auto activates
use CGI::OptimalQuery::ExportDataTool();
use CGI::OptimalQuery::SaveSearchTool();
use CGI::OptimalQuery::LoadSearchTool();

sub escapeHTML {
  return defined $_[0] ? CGI::escapeHTML($_[0]) : '';
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

  # check for required attributes
  confess "specified select is not a hash ref!"
    unless ref $$o{schema}{select} eq "HASH";
  confess "specified joins is not a hash ref!"
    unless ref $$o{schema}{joins} eq "HASH";
  
  # set defaults
  $$o{schema}{debug} ||= 0;
  $$o{schema}{check} = $ENV{'CGI-OPTIMALQUERY_CHECK'} 
    if ! defined $$o{schema}{check};
  $$o{schema}{check} = 0 if ! defined $$o{schema}{check};
  $$o{schema}{title} ||= "";
  $$o{schema}{options} ||= {};
  $$o{schema}{resourceURI} ||= $ENV{OPTIMALQUERY_RESOURCES} || '/OptimalQuery';

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

  # install the export tool
  CGI::OptimalQuery::ExportDataTool::activate($o);

  # if savedSearchUserID enable savereport and loadreport tools
  $$o{schema}{savedSearchUserID} ||= undef;
  if ($$o{schema}{savedSearchUserID} =~ /^\d+$/) {
    CGI::OptimalQuery::LoadSearchTool::activate($o);
    CGI::OptimalQuery::SaveSearchTool::activate($o);
  }

  # run on_init function for each enabled tool
  foreach my $v (values %{ $$o{schema}{tools} }) {
    $$v{on_init}->($o) if ref($$v{on_init}) eq 'CODE';
  }

  # set default page & rows_page if not already defined
  $$o{page} ||= $$o{q}->param('page') || 1;
  $$o{schema}{results_per_page_picker_nums} ||= [25,50,100,500,1000,'All'];
  $$o{rows_page} ||= $$o{q}->param('rows_page') || $$o{schema}{rows_page} || $$o{schema}{results_per_page_picker_nums}[0] || 10;
  $$o{show} ||= $$o{q}->param('show') || $$o{schema}{show};
  $$o{filter}       = (defined $$o{q}->param('filter'))       ? $$o{q}->param('filter')       : $$o{schema}{filter} || '';
  $$o{hiddenFilter} = (defined $$o{q}->param('hiddenFilter')) ? $$o{q}->param('hiddenFilter') : $$o{schema}{hiddenFilter} || '';
  $$o{queryDescr}   = (defined $$o{q}->param('queryDescr'))   ? $$o{q}->param('queryDescr')   : $$o{schema}{queryDescr} || '';
  $$o{sort}         = (defined $$o{q}->param('sort'))         ? $$o{q}->param('sort')         : $$o{schema}{sort} || '';

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

  return $o;
}

sub oq  { $_[0]{oq}  }

# ----------- UTILITY METHODS ------------------------------------------------

sub escape_html      { escapeHTML($_[1]) }
sub escape_uri       { CGI::escape($_[1])     }
sub escape_js        {
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

  # execute query
  $$o{sth}->execute( limit => $$o{limit} );

  return $$o{sth};
}
sub get_count        { $_[0]->sth->count() }
sub get_rows_page    { $_[0]{rows_page} }
sub get_current_page { $_[0]{page}      }
sub get_lo_rec       { $_[0]{limit}[0]  }
sub get_hi_rec       { $_[0]{limit}[1]  }
sub get_num_pages    { $_[0]{num_pages} }
sub get_title        { $_[0]{schema}{title} }
sub get_filter       { $_[0]->sth->filter_descr() }
sub get_sort         { $_[0]->sth->sort_descr() }
sub get_query        { $_[0]{query}     }
sub get_nice_name    { $_[0]{schema}{select}{$_[1]}[2] }
sub get_num_usersel_cols { scalar @{$_[0]{show}} }
sub get_usersel_cols { $_[0]{show} }

1;
