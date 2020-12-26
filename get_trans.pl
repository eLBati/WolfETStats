#!/usr/bin/perl

local $/ = undef;
$_ = <>;
$t{$_}++ for /\[T:([^\]]*)\]/g;
print "$_=\n" for keys %t;

