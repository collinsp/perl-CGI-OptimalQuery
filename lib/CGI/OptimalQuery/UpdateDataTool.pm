package CGI::OptimalQuery::UpdateDataTool;

use strict;
use warnings;
use JSON::XS;
no warnings qw( uninitialized );
use base 'CGI::OptimalQuery::Base';

sub escapeHTML { CGI::OptimalQuery::Base::escapeHTML(@_) }

sub output {
  my ($o) = @_;
  my $act = $$o{q}->param('act');
  my $funcName = "act_$act";
  my $codeRef = __PACKAGE__->can($funcName) || \&act_printform;
  $codeRef->(@_);
  return undef;
}

sub translate_db_error {
  my ($msg) = @_;

  if ($msg !~ /^DBD\:\:/) {
    $msg = ($msg =~ /(.*?)\ at\ /) ? $1 : $msg;
  }
  elsif ($msg =~ /error\ in\ your\ SQL\ syntax/) {
    $msg = "SQL syntax error";
  }
  elsif ($msg =~ /Lock\ wait\ timeout\ exceeded/) {
    $msg = "Another user is trying to modify this resource. Please wait and try again.";
  }
  elsif ($msg =~ /\ Column\ \'(\w+)\'\ cannot\ be\ null/) {
    $msg = "'$1' is a required field.";
  }
  elsif ($msg =~ /Duplicate\ entry\ \'([^\']+)\'\ for\ key\ \'(\w+)\'/) {
    my $val = $1;
    my $field = $2;
    $msg =  "Cannot save multiple records with this same value '$val'";
    $msg .= " for $field" if $field =~ /\D/;
    $msg .= ".";
  }
  elsif ($msg =~ /Duplicate\ entry\ \'([\']+)\'/) {
    $msg = "Another record already exists with value '$1'";
  }
  elsif ($msg =~ /Data\ truncated\ for\ column\ \'([^\']+)/) {
    $msg = "Invalid input for field $1.";
  }
  elsif ($msg =~ /Data\ too\ long\ for\ column\ \'([^\']+)/) {
    $msg = "Data too long for field $1.";
  }
  elsif ($msg =~ /foreign\ key\ constraint\ fails/) {
    $msg = "You cannot delete this record because another record has associated this record.";
  }
  elsif ($msg =~ /Incorrect integer value\: \'\' for column \'([^\']+)\'/) {
    $msg = "'$1' is a required field.";
  }

  return $msg;
}


sub act_save {
  my ($o) = @_;
  $o->csrf_check();
  my %values;
  { my @fields = $$o{q}->param('fields');
    my @values = $$o{q}->param('values');
    @values{@fields}=@values;
  }

  my %rv;
  eval {
    $$o{dbh}->begin_work();

    my %updateOpts;
    $updateOpts{filter} = $$o{filter} if $$o{filter} ne '';
    $updateOpts{hiddenFilter} = $$o{hiddenFilter} if $$o{hiddenFilter} ne '';
    $updateOpts{forceFilter} = $$o{forceFilter} if $$o{forceFilter} ne '';
    $updateOpts{newValues} = \%values;

    # give OQ an arrayref to populate with previous values if an after_update_handler is defined
    $updateOpts{oldValues} = [] if ref($$o{schema}{after_update_handler}) eq 'CODE';

    my $numupdated = $$o{oq}->update(%updateOpts);

    $$o{schema}{after_update_handler}->(%updateOpts)
      if $numupdated > 0 && ref($$o{schema}{after_update_handler}) eq 'CODE';

    $$o{dbh}->commit();
    $rv{status} = 'ok';
  }; if ($@) {
    my $msg = $@;
    $$o{dbh}->rollback();
    $rv{status} = 'error';
    $rv{msg} = translate_db_error($msg);
  }

  $$o{output_handler}->($$o{httpHeader}->('application/json').encode_json(\%rv));
  return undef;
}

sub act_printform {
  my ($o) = @_;
  
  my $buf = $$o{httpHeader}->('text/html').
"<!DOCTYPE html>
<html>
<body>
<div class=OQUpdateDataToolPanel>
  <h1>update data</h1>
  <div class=OQpanelMsg></div>
  <table summary='table of fields to update' class=grid>
    <thead>
      <tr><td>field to update</td><td>set value</td><td></td></tr>
    </thead>
    <tbody>";
  my $typeMap = $o->{oq}->get_col_types('select');
  my @fields = $$o{q}->param('fields');
  my @values = $$o{q}->param('values');

  my %seenfield;
  for (my $i=0; $i<=$#fields; ++$i) {
    next if ! $$o{oq}->canUpdate($fields[$i]) || $seenfield{$fields[$i]};
    $seenfield{$fields[$i]}=1;
    my $type = $$typeMap{$fields[$i]} || 'char';
    $buf .= "
      <tr>
      <td><input name=fields readonly type=hidden value='".escapeHTML($fields[$i])."'>".escapeHTML($o->get_nice_name($fields[$i]))."</td>
      <td><input title='enter update value; omit value to clear (set to null) the current value' name=values type=text class=type-$type value='".escapeHTML($values[$i])."'></td>
      <td><button type=button class=OQDelRow>&#10005;</button>
      </tr>";
  }
  $buf .= "</tbody>
  </table>
  <div style='margin-top:1em; text-align: center;'>
    <label>Select more fields to update
    <br>
    <select class=fieldToUpdate><option value=''></option>";

  # get list of editable fields sorted by label
  my @editableFields =
    sort { $o->get_nice_name($a) cmp $o->get_nice_name($b) }
    grep { $$o{oq}->canUpdate($_) }
    keys %{ $$o{schema}{select} };

  foreach my $selectAlias (@editableFields) {
    my $label = $o->get_nice_name($selectAlias);
    $buf .= "<option value='".escapeHTML($selectAlias)."'>".escapeHTML($label);
  }
  $buf .= "</select>
    </label>
  </div>
  <hr>
  <div style='margin:.5em auto; text-align: center;'>
    <button type=button class=OQUpdateDataToolCancelBut>cancel</button>
    <button type=button class=OQUpdateDataToolOKBut style='margin-left:2em;'>update records</button>
  </div>
</div>
</body>
</html>";

  $$o{output_handler}->($buf);
  return undef;
}

1;
