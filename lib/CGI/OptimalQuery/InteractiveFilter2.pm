package CGI::OptimalQuery::InteractiveFilter2;

use strict;
use warnings;
no warnings qw( uninitialized );
use base 'CGI::OptimalQuery::Base';


use CGI qw(escapeHTML);

# returns [
#  'AND' , 'OR',
#  [1,$numLeftParen,$leftExp,$op,$rightExp,$numRightParen],
#  [2,$numLeftParen,$namedFilter,$argArray,$numRightParen]
# ]
sub parseFilter {
  my ($o,$f) = @_;
  $f =~ /\G\s+/gc;
  my @filter;
  return \@filter if $f eq '';
  my $labelMap;
  while (1) {
    my $lp=0;
    my $rp=0;
    while ($f =~ /\G\(\s*/gc) { $lp++; }
    if ($f=~/\G(\w+)\s*\(\s*/gc) { 
      my $namedFilter = $1;
      die "Invalid named filter $namedFilter at: ".substr($f, 0, pos($f)).' <*> '.substr($f,pos($f))
        unless exists $$o{schema}{named_filters}{$namedFilter};

      # parse named filter arguments
      my @args;
      while (1) {
        # closing paren so end
        if ($f=~/\G\)\s*/gc) {
          last;
        }

        # single quoted value OR double quoted value OR no whitespace literal
        elsif ($f=~/\G\'([^\']*)\'\s*/gc || $f=~/\G\"([^\"]*)\"\s*/gc || $f=~/\G(\w+)\s*/gc) {
          push @args, $1;
        }

        # , => : separator so do nothing
        elsif ($f =~ /\G(\,|\=\>|\:)\s*/gc) {
          # noop
        }
        else {
          die "Invalid named filter $namedFilter - missing right paren at: ".substr($f, 0, pos($f)).' <*> '.substr($f,pos($f));
        }
      }
      while ($f =~ /\G\)\s*/gc) { $rp++; }
      push @filter, [2,$lp,$namedFilter,\@args,$rp];
    }
    else {
      my $lexp;
      if ($f=~/\G\[([^\]]+)\]\s*/gc || $f=~/\G(\w+)\s*/gc) { $lexp = $1; }
      else { die 'Missing left expression: '.substr($f, 0, pos($f)).' <*> '.substr($f,pos($f)); }
      if (! exists $$o{schema}{select}{$lexp}) {
        if (! $labelMap) {
          $labelMap = {};
          while (my ($k,$v) = each %{ $$o{schema}{select} }) {
            my $v = uc($$v[2]); $v =~ s/\s//g;
            $$labelMap{uc($k)}=$k;
            $$labelMap{uc($$v[2])}=$k;
          }
        }
        $lexp = uc($lexp); $lexp =~ s/\s//g;
        $lexp=$$labelMap{$lexp};
        die "Invalid field $lexp at: ".substr($f, 0, pos($f)).' <*> '.substr($f,pos($f))
          unless $lexp;
      }
      my $op;
      if ($f =~ /\G(\!\=|\=|\<\=|\>\=|\<|\>|like|not\ like|contains|not\ contains)\s*/gc) { $op = $1; }
      else { die 'Missing operator: '.substr($f, 0, pos($f)).' <*> '.substr($f,pos($f)); }
      my $rexp;
      if ($f=~/\G\'([^\']*)\'\s*/gc || $f=~/\G\"([^\"]*)\"\s*/gc || $f=~/\G(\w+)\s*/gc) { $rexp = $1; }
      else { die 'Missing right expression: '.substr($f, 0, pos($f)).' <*> '.substr($f,pos($f)); }
      while ($f =~ /\G\)\s*/gc) { $rp++; }
      push @filter, [1,$lp, $lexp, $op, $rexp, $rp];
    }
    if ($f =~ /(AND|OR)\s*/gci) { push @filter, uc($1); }
    else { last; }
  }
  return \@filter;
}

sub output {
  my $o = shift;
  my $buf = CGI::header('text/html')."<!DOCTYPE html>\n<html><body><div class=OQFilterPanel><h1>filter</h1><table>";
  my $types = $$o{oq}->get_col_types('filter');

  my $s = $$o{schema}{select};
  my @cols = grep {
    $$s{$_}[2] ne '' && ! $$s{$_}[3]{disable_filter} && ! $$s{$_}[3]{is_hidden}
  } sort { $$s{$a}[2] cmp $$s{$b}[2] } keys %$s;
  my @op = (qw( = != < <= > >= like ), 'not like', 'contains', 'not contains');

  my $parsedFilter = parseFilter($o,$$o{q}->param('filter'));
  foreach my $f (@$parsedFilter) {
    $buf .= "<tr>";
    if (ref($f) ne 'ARRAY') {
      $buf .= "<td colspan=6><select class=logicop><option>AND<option";
      $buf .= " selected" if $f eq 'OR';
      $buf .= ">OR</select></td>";
    } elsif ($$f[0]==1) {
      $buf .= "<td>";
      my ($type,$numLeftParen,$leftExp,$operator,$rightExp,$numRightParen) = @$f;
      if ($numLeftParen == 0) {
        $buf .= "<button type=button class=lp>(</button>";
      } else {
        $buf .= "<select class=lp><option value=''> </option><option";
        $buf .= " selected" if $numLeftParen==1;
        $buf .= ">(<option";
        $buf .= " selected" if $numLeftParen==2;
        $buf .= ">((<option";
        $buf .= " selected" if $numLeftParen==3;
        $buf .= ">(((</select>";
      }
      $buf .= "</td><td><select class=lexp>";
      foreach my $c (@cols) {
        $buf .= "<option value='[".escapeHTML($c)."]'";
        $buf .= " data-type=".$$types{$c} if $$types{$c} ne 'char';
        $buf .= " selected" if $c eq $leftExp;
        $buf .= ">".escapeHTML($$o{schema}{select}{$c}[2]);
      }
      $buf .= "</select></td><td><select class=op>";
      foreach my $op (@op) {
        $buf .= "<option";
        $buf .= " selected" if $op eq $operator;
        $buf .= ">$op";
      }
      $buf .= "</select></td><td><input type=text class=rexp value='".escapeHTML($rightExp)."'></td><td>";
      if ($numRightParen == 0) {
        $buf .= "<button type=button class=rp>)</button>";
      } else {
        $buf .= "<select class=rp><option value=''> </option><option";
        $buf .= " selected" if $numRightParen==1;
        $buf .= ">)<option";
        $buf .= " selected" if $numRightParen==2;
        $buf .= ">))<option";
        $buf .= " selected" if $numRightParen==3;
        $buf .= ">)))</select>";
      }
      $buf .= "</td><td><button type=button class=DeleteFilterElemBut>x</button></td>";
    } else {
      $buf .= "<td>";
      my ($type,$numLeftParen,$namedFilter,$argArray,$numRightParen) = @$f; 
      if ($numLeftParen == 0) {
        $buf .= "<button type=button class=lp>(</button>";
      } else {
        $buf .= "<select class=lp><option value=''> </option><option";
        $buf .= " selected" if $numLeftParen==1;
        $buf .= ">(<option";
        $buf .= " selected" if $numLeftParen==2;
        $buf .= ">((<option";
        $buf .= " selected" if $numLeftParen==3;
        $buf .= ">(((</select>";
      }
      $buf .= "</td><td colspan=3><input type=hidden value='".escapeHTML($namedFilter)."('>";
      my $nf = $$o{schema}{named_filters}{$namedFilter};
      if (ref($nf) eq 'ARRAY') {
        my $title = $$nf[2] || $namedFilter;
        $buf .= "<span>".escapeHTML($title)."</span>";
        for (my $i=0; $i <= $#$argArray; $i+=2) { 
          $buf .= "<input type=hidden name='".escapeHTML("arg_$$argArray[$i]")."' value='".escapeHTML("arg_$$argArray[$i]").">";
        }
      }
      elsif (ref($nf) eq 'HASH') {
        if (ref($$nf{html_generator}) eq 'CODE') {
          #before we call the html_generator, set the params up
          my %args;
          for (my $i=0; $i <= $#$argArray; $i+=2) { 
            my $name = $$argArray[$i];
            my $val  = $$argArray[$i + 1];
            $args{$name}||=[];
            push @{$args{$name}}, $val;
          }
          while (my ($name,$vals) = each %args) {
            $$o{q}->param('arg_'.$name,@$vals);
          }
          $buf .= $$nf{html_generator}->($$o{q}, 'arg_');
        } else {
          my $title = $$nf{title} || $namedFilter;
          $buf .= "<span>".escapeHTML($title)."</span>";
          for (my $i=0; $i <= $#$argArray; $i+=2) { 
            my $name = $$argArray[$i];
            my $val  = $$argArray[$i + 1];
            $buf .= "<input type=hidden name='arg_".escapeHTML($name)."' value='".escapeHTML($val)."'>";
          }
        }
      }
      $buf .= "<input type=hidden value=')'>";
      $buf .= "</td><td>";
      if ($numRightParen == 0) {
        $buf .= "<button type=button class=rp>)</button>";
      } else {
        $buf .= "<select class=rp><option value=''> </option><option";
        $buf .= " selected" if $numRightParen==1;
        $buf .= ">)<option";
        $buf .= " selected" if $numRightParen==2;
        $buf .= ">))<option";
        $buf .= " selected" if $numRightParen==3;
        $buf .= ">)))</select>";
      }
      $buf .= "</td><td><button type=button class=DeleteFilterElemBut>x</button></td>";
    }
    $buf .= "</tr>";
  }
  $buf .= "</table><br>";

  $buf .= "<select class=newfilter><option value=''>-- add new filter element</option><optgroup label='Column to compare:'>";

  foreach my $c (@cols) {
    $buf .= "<option value='".escapeHTML($c)."'";
    $buf .= " data-type=".$$types{$c} if $$types{$c} ne 'char';
    $buf .= ">".escapeHTML($$o{schema}{select}{$c}[2]);
  }
  $buf .= "</optgroup>";
  my $f = $$o{schema}{named_filters};
  my @k = sort {
    ((ref($$f{$a}) eq 'ARRAY') ? $$f{$a}[2] : $$f{$a}{title}) cmp
    ((ref($$f{$b}) eq 'ARRAY') ? $$f{$b}[2] : $$f{$b}{title}) } keys %$f;
  if ($#k > -1) {
    $buf .= "<optgroup label='Named Filters:'>";
    foreach my $alias (@k) {
      my $label;
      if (ref($$f{$alias}) eq 'ARRAY') {
        $label = $$f{$alias}[2];
      } else {
        $label = $$f{$alias}{title};
      }
      next unless $label;
      $buf .= "<option value='".escapeHTML($alias)."()'>".escapeHTML($label);
    }
    $buf .= "</optgroup>";
  }
  $buf .= "</select><br><button type=button class=CancelFilterBut>cancel</button><button type=button class=OKFilterBut>ok</button></div></body></html>";

  $$o{output_handler}->($buf);
  return undef;
}

1;
