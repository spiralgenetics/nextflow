#!/usr/bin/env nextflow

def helpMessage() {
    log.info """
    Usage:
    The typical command for running the pipeline is as follows:
    nextflow run main.nf --bams sample.bam [Options]

    Inputs Options:
    --input_tsv         Input file
    --license           License file
    --reference_tar_gz  Reference.tar.gz ref dir file

    Resource Options:
    --max_cpus      Maximum number of CPUs (int)
                    (default: $params.max_cpus)  
    --max_memory    Maximum memory (memory unit)
                    (default: $params.max_memory)
    --max_time      Maximum time (time unit)
                    (default: $params.max_time)
    See here for more info: https://github.com/lifebit-ai/hla/blob/master/docs/usage.md
    """.stripIndent()
}

// Show help message
if (params.help) {
  helpMessage()
  exit 0
}

// Define Channels from input
Channel
    .fromPath(params.input_tsv)
    .ifEmpty { exit 1, "Cannot find input file : ${params.input_tsv}" }
    .splitCsv(skip:1, sep:'\t')
    .map { participant_id, participant_type, bam -> [ participant_id, participant_type, file(bam) ] }
    .into { ch_input; ch_input_to_view }

ch_input_to_view.view()
ch_reference_tar_gz = Channel.value(file(params.reference_tar_gz))
ch_license = Channel.value(file(params.license))

// Define Process
process biograph {
    tag "$participant_id"
    publishDir "${params.outdir}/${participant_type}", mode: 'copy'
    beforeScript 'eval "$(aws ecr get-login --registry-ids 084957857030 --no-include-email --region eu-west-2)" && docker pull 084957857030.dkr.ecr.eu-west-2.amazonaws.com/releases:biograph-6.0.5'

    input:
    set val(participant_id), val(participant_type), file(bam) from ch_input
    each file(reference_tar_gz) from ch_reference_tar_gz
    each file(license) from ch_license

    output:
    file "mock_${participant_id}.txt" into ch_out
    file "*.qc.txt" into ch_out
    file "*.vcf"

    script:
    """
    mkdir -p tmp
    tar xvfz $reference_tar_gz
    echo "Finished expanding tarball"
    biograph license

    ls -l
    echo "participant_id:" $participant_id
    echo "participant_type:" $participant_type
    touch mock_${participant_id}.txt
    touch mock_${participant_id}.qc.txt
    touch mock_${participant_id}.vcf
    echo "Finished mock file touch"

    echo "Starting BG full pipeline"
    biograph full_pipeline --biograph ${participant_id}.bg --ref $reference_tar_gz.simpleName \
    --reads $bam \
    --model /app/biograph_model.ml \
    --tmp ./tmp \
    --create "--max-mem 100 --format bam" \
    --discovery "--bed $reference_tar_gz.simpleName/regions_chr1p.bed"
    
    if [ -d ${participant_id}.bg ]i; then
        if [ -f ${participant_id}.bg/analysis/results.vcf ]; then
            mv ${participant_id}.bg/analysis/results.vcf ${participant_type}_${participant_id}.vcf
        fi
        if [ -d ${participant_id}.bg/qc ]; then
            for x in ${participant_id}.bg/qc/*; do
                mv ${x} $(basename ${x})-${participant_type}_${participant_id}.qc.txt
            done 
       fi
    fi
    """
  }

