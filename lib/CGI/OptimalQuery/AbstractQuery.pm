package CGI::OptimalQuery::AbstractQuery;

use strict;
use warnings;
no warnings qw( uninitialized );
use base 'CGI::OptimalQuery::Base';

sub new {
  my $pack = shift;
  my $o = $pack->SUPER::new(@_);

  # load HTML form params or use values in schema
  for (qw( show filter sort page rows_page module queryDescr hiddenFilter )) {
    if (defined $$o{q}->param($_)) {
      $$o{$_} = $$o{q}->param($_);
    } else {
      $$o{$_} = $$o{schema}{$_};
    }
  }

  # convert show & sort into array
  if (! ref($$o{show})) {
    my @ar = split /\,/, $$o{show};
    $$o{show} = \@ar;
  } 

  # set default page & rows_page if not already defined
  $$o{page} ||= 1;
  $$o{schema}{results_per_page_picker_nums} ||= [25,50,100,500,1000,'All'];
  $$o{rows_page} ||= $$o{schema}{rows_page} || $$o{schema}{results_per_page_picker_nums}[0] || 10;
  $$o{hiddenFilter} ||= '';
  $$o{queryDescr} ||= '';

  # if any fields are passed into on_select, ensure they are always selected
  my $on_select = $$o{q}->param('on_select');
  if ($on_select =~ /[^\,]+\,(.+)/) {
    my @fields = split /\,/, $1;
    for (@fields) {
      $$o{oq}{'select'}{$_}[3]{always_select}=1
        if exists $$o{oq}{'select'}{$_};
    }
  }

  # if we still don't have something to show then show all cols
  # that aren't hidden
  if (! scalar( @{ $$o{show} } )) {
    for (keys %{ $$o{schema}{select} }) {
      push @{$$o{show}}, $_ unless $$o{oq}->{'select'}->{$_}->[3]->{is_hidden};
    }
  }

  # check schema validity
  $$o{oq}->check_join_counts() if $$o{schema}{check} && ! defined $$o{q}->param('module');

  # create & execute SQL statement
  $$o{sth} ||= $$o{oq}->prepare(
    show   => $$o{show},
    filter => $$o{filter},
    hiddenFilter => $$o{hiddenFilter},
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

  return $o;
}

#-------------- ACCESSORS --------------------------------------------------
sub sth              { $_[0]{sth} }
sub get_count        { $_[0]{sth}->count() }
sub get_rows_page    { $_[0]{rows_page} }
sub get_current_page { $_[0]{page}      }
sub get_lo_rec       { $_[0]{limit}[0]  }
sub get_hi_rec       { $_[0]{limit}[1]  }
sub get_num_pages    { $_[0]{num_pages} }
sub get_title        { $_[0]{schema}{title} }
sub get_filter       { $_[0]{sth}->filter_descr() }
sub get_sort         { $_[0]{sth}->sort_descr() }
sub get_query        { $_[0]{query}     }
sub get_nice_name    { $_[0]{schema}{select}{$_[1]}[2] }
sub get_num_usersel_cols { scalar @{$_[0]{show}} }
sub get_usersel_cols { $_[0]{show} }

1;
