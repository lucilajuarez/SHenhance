=head1 COPYRIGHT NOTICE

Photonic - A perl package for calculations on photonics and
metamaterials.

Copyright (C) 1916 by W. Luis Mochán

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 1, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA  02110-1301 USA

    mochan@fis.unam.mx

    Instituto de Ciencias Físicas, UNAM
    Apartado Postal 48-3
    62251 Cuernavaca, Morelos
    México

=cut

use strict;
use warnings;
use PDL;
use PDL::NiceSlice;
use PDL::Complex;
use Photonic::Geometry::FromEpsilon;
use Photonic::WE::S::Metric;
use Photonic::WE::S::AllH;
use Photonic::WE::S::Green;

use Machine::Epsilon;
use List::Util;

use Test::More tests => 4;

sub agree {
    my $a=shift;
    my $b=shift//0;
    return (($a-$b)*($a-$b))->sum<=1e-7;
}

sub Cagree {
    my $a=shift;
    my $b=shift//0;
    return (($a-$b)->Cabs2)->sum<=1e-7;
}

#Check green for simple 1D system
my ($ea, $eb)=(r2C(1), r2C(2));
my $f=6/11;
my $eps=$ea*(zeroes(11,1)->xvals<5)+ $eb*(zeroes(11,1)->xvals>=5)+0*i;
my $g=Photonic::Geometry::FromEpsilon
    ->new(epsilon=>$eps);
my $m=Photonic::WE::S::Metric->new(
    geometry=>$g, epsilon=>pdl(1), wavenumber=>pdl(2e-5),
    wavevector=>pdl([1,0])*1e-8);
my $gr=Photonic::WE::S::Green->new(nh=>10, metric=>$m);
my $grv=$gr->greenTensor;
ok(Cagree($grv->(:,(0),(0)), ($f/$eb+(1-$f)/$ea)),
			     "1D long non retarded");
ok(Cagree($grv->(:,(1),(1)), 1/($f*$eb+(1-$f)*$ea)),
			     "1D transverse non retarded");
ok(Cagree($grv->(:,(0),(1)), 0),
			     "1D l-t non retarded");
ok(Cagree($grv->(:,(1),(0)), 0),
			     "1D t-l non retarded");
