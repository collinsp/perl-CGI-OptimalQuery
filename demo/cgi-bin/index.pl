#!/usr/bin/perl

use strict;
use CGI();

print CGI::header(), 
"<!DOCTYPE html>
<html>
<body>
  <h1>My Simple Dashboard</h1>
  <ul>
    <li><a href=inventory.pl target=_blank>inventory</a>
    <li><a href=people.pl target=_blank>people</a>
    <li><a href=product.pl target=_blank>product</a>
    <li><a href=manufact.pl target=_blank>manufacturers</a>
  </ul>
</body>
</html>";
