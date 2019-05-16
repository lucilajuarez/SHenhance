=head1 NAME

Photonic::LE::S::Field

=head1 VERSION

version 0.011

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

=head1 SYNOPSIS

   use Photonic::LE::S::Field;
   my $nrf=Photonic::LE::S::Field->new(...);
   my $field=$nrf->evaluate();

=head1 DESCRIPTION

Calculates the non retarded electric field for a given fixed
Photonic::Geometry structure and given dielectric functions of
the components.

=head1 METHODS

=over 4

=item * new(nr=>$nr, nh=>$nh, smallE=>$smallE)

Initializes the structure.

$nr Photonic::LE::S::AllH is a Haydock calculator for the
structure, *initialized* with the flag keepStates=>1
(Photonic::Types::LE::S::AllHSave, as defined in Photonic::Types).

$nh is the maximum number of Haydock coefficients to use.

$smallE is the criteria of convergence (default 1e-7) for
Field calculations

=item * evaluate()

Returns the microscopic electric field.

=back

=head1 ACCESORS (read only)

=over 4

=item * nr

Photonic::LE::S::AllH structure

=item * nh

Maximum number of Haydock coefficients to use.

=item * smallE

Criteria of convergence. 0 means don't check. From Photonic::Roles::EpsParams

=item * epsA

Dielectric function of component A

=item * epsB

Dielectric function of componente B

=item * u

Spectral variable

=item * Es

Array of field coefficients

=item * filter

optional reciprocal space filter

=item * field

real space field in format RorI, cartesian, nx, ny,...

=item * epsL

Longitudinal dielectric response, obtained colateraly from last
evaluation of the field

=back

=begin Pod::Coverage

=head2 BUILD

=end Pod::Coverage

=cut

package Photonic::LE::S::Field;
$Photonic::LE::S::Field::VERSION = '0.011';

use namespace::autoclean;
use PDL::Lite;
use PDL::NiceSlice;
use PDL::Complex;
use PDL::FFTW3;
use Photonic::LE::S::AllH;
use Photonic::ExtraUtils qw(cgtsl);
use Photonic::Types;
use Photonic::Iterator qw(nextval);
use Moose;
use MooseX::StrictConstructor;

has 'nr'=>(is=>'ro', isa=>'Photonic::Types::LE::S::AllHSave', required=>1,
           documentation=>'Haydock recursion calculator');
has 'Es'=>(is=>'ro', isa=>'ArrayRef[PDL::Complex]', init_arg=>undef,
           writer=>'_Es', documentation=>'Field coefficients');
has 'filter'=>(is=>'ro', isa=>'PDL', predicate=>'has_filter',
               documentation=>'Optional reciprocal space filter');
has 'field'=>(is=>'ro', isa=>'PDL::Complex', init_arg=>undef,
           writer=>'_field', documentation=>'Calculated real space field');
has 'epsL' =>(is=>'ro', isa=>'PDL::Complex', init_arg=>undef,
		 writer=>'_epsL',
		 documentation=>'Longitudinal dielectric response');
with 'Photonic::Roles::EpsParams';

sub BUILD {
    my $self=shift;
    $self->nr->run unless $self->nr->iteration;
}

sub evaluate {
    my $self=shift;
    my $as=$self->nr->as;
    my $b2s=$self->nr->b2s;
    my $bs=$self->nr->bs;
    my $stateit=$self->nr->state_iterator;
    my $nh=$self->nh; #desired number of Haydock terms
    #don't go beyond available values.
    $nh=$self->nr->iteration if $nh>$self->nr->iteration;
    # calculate using linpack for tridiag system
    # solve \epsilon^LL \vec E^L=D^L.
    # At first take D=|0>
    my $diag=PDL->pdl($as)->(:,0:$nh-1)->complex;
    my $subdiag=PDL->pdl($bs)->(:,0:$nh-1)->complex;
    # rotate complex zero from first to last element.
    my $supradiag=$subdiag->real->mv(0,-1)->rotate(-1)->mv(-1,0)->complex;
    my $rhs=PDL->zeroes($nh);
    $rhs->((0)).=1;
    $rhs=$rhs->r2C;
    my ($result, $info)= cgtsl($subdiag, $diag, $supradiag, $rhs);
    die "Error solving tridiag system" unless $info == 0;
    # Obtain longitudinal macroscopic response from result
    # Add spinor normalization.
    $self->_epsL(my $epsL=sqrt(2)/$result->(:,(0)));
    # Normalize result so macroscopic field is 1.
    $result*=$epsL;
    my @Es= map {PDL->pdl($_)->complex} @{$result->unpdl};
    #states are ri,nx,ny...
    #field is ri,xy,pm,nx,ny...
    my $ndims=$self->nr->B->ndims; # num. of dims of space
    my @dims=$self->nr->B->dims; # actual dims of space
    my $field_G=PDL->zeroes(2, $ndims, 2, @dims)->complex;
    for(my $n=0; $n<$nh; ++$n){
	#state is ri,pm,nx,ny...
	#pmGnorm is xy,pm,nx,ny...
	#$Gpsi_G is ri,xy,pm,nx,ny
	my $GPsi_G=($self->nr->pmGNorm->mv(0,-1)*nextval($stateit))
	    ->mv(-1,1); #^G|psi_n>
	my $EnGPsi_G=$Es[$n]*$GPsi_G; #En ^G|psi_n>
	$field_G+=$EnGPsi_G; #ri,xy,pm,nx,ny...
    }
    #Choose +k
    my $Esp=$field_G->(:,:,(0)); #ri,xy,nx,ny
    #filter RandI for each cartesian
    $Esp *= $self->filter->(*1) if $self->has_filter;
    #get cartesian out of the way, fourier transform, put cartesian.
    my $field_R=ifftn($Esp->mv(1,-1)->real, $ndims)->mv(-1,1)->complex;
    $field_R*=$self->nr->B->nelem; #scale to have unit macroscopic field
    #result is ri,xy,nx,ny,...
    $self->_field($field_R);
    #my $EM=$field_R->mv(0,-1)->mv(0,-1)->clump(-3)->mv(-2,0)->sumover->mv(-1,1)/$self->nr->B->nelem;
    #print "EM=$EM\n";
    return $field_R;
}


__PACKAGE__->meta->make_immutable;

1;
