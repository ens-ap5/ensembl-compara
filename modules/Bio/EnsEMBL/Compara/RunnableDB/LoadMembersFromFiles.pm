
=pod 

=head1 NAME

Bio::EnsEMBL::Compara::RunnableDB::LoadOneGenomeDB

=head1 DESCRIPTION

This Runnable loads one entry into 'genome_db' table and passes on the genome_db_id.

The format of the input_id follows the format of a Perl hash reference.
Examples:
    { 'species_name' => 'Homo sapiens', 'assembly_name' => 'GRCh37' }
    { 'species_name' => 'Mus musculus' }

supported keys:
    'locator'       => <string>
        one of the ways to specify the connection parameters to the core database (overrides 'species_name' and 'assembly_name')

    'species_name'  => <string>
        mandatory, but what would you expect?

    'assembly_name' => <string>
        optional: in most cases it should be possible to find the species just by using 'species_name'

    'genome_db_id'  => <integer>
        optional, in case you want to specify it (otherwise it will be generated by the adaptor when storing)

=cut

package Bio::EnsEMBL::Compara::RunnableDB::LoadMembersFromFiles;

use strict;
use warnings;

use Bio::EnsEMBL::Compara::Member;
use Bio::EnsEMBL::Compara::Subset;

use Data::Dumper;

use base ('Bio::EnsEMBL::Compara::RunnableDB::BaseRunnable');


sub fetch_input {
	my $self = shift @_;

	# Adaptors
	my $compara_dba = $self->compara_dba();
	$self->param('member_adaptor', $compara_dba->get_MemberAdaptor());
      $self->param('sequence_adaptor', $compara_dba->get_SequenceAdaptor());

      $self->param('genome_content', $compara_dba->get_GenomeDBAdaptor->fetch_by_dbID($self->param('genome_db_id'))->db_adaptor);

}

sub write_output {
	my $self = shift @_;

	my $genome_db_id = $self->param('genome_db_id');
	my $member_adaptor = $self->param('member_adaptor');

      print Dumper($self->param('genome_content')) if $self->debug;
      my $prot_seq = $self->param('genome_content')->get_protein_sequences;
      my $cds_seq = $self->param('genome_content')->get_cds_sequences;
      my $gene_coordinates = $self->param('genome_content')->get_gene_coordinates;
      my $cds_coordinates = $self->param('genome_content')->get_cds_coordinates;
      my $taxon_id = $self->param('genome_content')->get_taxonomy_id;

	my $count = 0;
      foreach my $gene_name (keys %$prot_seq) {
		
		$count++;
            my $sequence = $prot_seq->{$gene_name};

		print "sequence $count: name ", $sequence->id, "\n" if ($self->debug > 1);
		print "sequence $count: description ", $sequence->desc, "\n" if ($self->debug > 1);
		print "sequence $count: length ", $sequence->length, "\n" if ($self->debug > 1);

		my $gene_member = Bio::EnsEMBL::Compara::Member->new();
    		$gene_member->stable_id($gene_name);
		$gene_member->display_label($sequence->id);
		$gene_member->source_name("ENSEMBLGENE");
		$gene_member->taxon_id($taxon_id);
		$gene_member->description($sequence->desc);
		$gene_member->genome_db_id($genome_db_id);
            if (exists $gene_coordinates->{$sequence->id}) {
                my $coord = $gene_coordinates->{$sequence->id};
                $gene_member->chr_name($coord->[0]);
                $gene_member->chr_start($coord->[1]);
                $gene_member->chr_end($coord->[2]);
                $gene_member->chr_strand($coord->[3]);
            } else {
                warn $sequence->id, " does not have gene coordinates\n";
            }

            #print Dumper($gene_member);
		$member_adaptor->store($gene_member);

		my $pep_member = Bio::EnsEMBL::Compara::Member->new();
		$pep_member->stable_id($gene_name);
		$pep_member->display_label($sequence->id);
		$pep_member->source_name("ENSEMBLPEP");
		$pep_member->taxon_id($taxon_id);
		$pep_member->description($sequence->desc);
		$pep_member->genome_db_id($genome_db_id);
            $pep_member->gene_member_id($gene_member->dbID);
            if (exists $cds_coordinates->{$sequence->id}) {
                my $coord = $cds_coordinates->{$sequence->id};
                $pep_member->chr_name($coord->[0]);
                $pep_member->chr_start($coord->[1]);
                $pep_member->chr_end($coord->[2]);
                $pep_member->chr_strand($coord->[3]);
            } else {
                warn $sequence->id, " does not have cds coordinates\n";
            }
		my $seq = $sequence->seq;
		$seq =~ s/O/X/g;
		$pep_member->sequence($seq);
		$member_adaptor->store($pep_member);
            $member_adaptor->_set_member_as_canonical($pep_member);

            if (exists $cds_seq->{$sequence->id}) {
                $pep_member->sequence_cds( $cds_seq->{$sequence->id}->seq );
                $self->param('sequence_adaptor')->store_other_sequence($pep_member, $cds_seq->{$sequence->id}->seq, 'cds');
            } elsif ($self->param('need_cds_seq')) {
                die $sequence->id, " does not have cds sequence\n";
            } else {
                warn $sequence->id, " does not have cds sequence\n";
            } 
      };

	print "$count genes and peptides loaded\n" if ($self->debug);
}

1;

