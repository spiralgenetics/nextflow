#!/usr/bin/env nextflow

def helpMessage() {
    log.info """
    Usage:
    The typical command for running the pipeline is as follows:
    nextflow run main.nf --bams sample.bam [Options]
    
    Inputs Options:
    --input         Input file

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
    .fromPath(params.input)
    .ifEmpty { exit 1, "Cannot find input file : ${params.input}" }
    .splitCsv(skip:1, sep:'\t')
    .map { participant_id, participant_type, bam -> [ participant_id, participant_type, bam ] }
    .into { ch_input; ch_input_to_view }

ch_input_to_view.view()
// ch_model = Channel.value(file(params.model))
// ch_reference_tar_gz = Channel.value(file(params.reference_tar_gz))
// ch_license = Channel.value(file(params.license))

// Define Process
process bgwrapper {
    tag "$participant_id"
    publishDir "${params.outdir}/${participant_type}", mode: 'copy'

    input:
    set val(participant_id), val(participant_type), file(bam) from ch_input
    // each file(model) from ch_model
    // each file(reference_tar_gz) from ch_reference_tar_gz
    // each file(license) from ch_license

    output:
    file "mock_${participant_id}.txt" into ch_out
    file "*.vcf"

    script:
    """
    # mkdir tmp
    # tar xvfz $reference_tar_gz
    # biograph full_pipeline --biograph ${participant_id}.bg --ref $reference_tar_gz.simpleName \
    # --reads $bam \
    # --model $model \
    # --tmp ./tmp
    # mv ${participant_id}.bg/analysis/results.vcf ${participant_type}_${participant_id}.vcf

    ls -l
    echo "participant_id:" $participant_id
    echo "participant_type:" $participant_type
    touch mock_${participant_id}.txt
    touch mock_${participant_id}.vcf
    """
    
  }

