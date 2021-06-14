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
    set file("${participant_id}.bg/qc/create_log.txt"),file("mock_${participant_id}.vcf"),file("*.log") into ch_out
    file "*.txt"

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
    touch mock_${participant_id}.vcf
    echo "Finished mock file touch"

    echo "Starting BG full pipeline"
    biograph full_pipeline --biograph ${participant_id}.bg --ref $reference_tar_gz.simpleName \
    --reads $bam \
    --model /app/biograph_model.ml \
    --tmp ./tmp \
    --threads ${task.cpus} \
    --create "--max-mem 100 --format bam" \
    --discovery "--bed $reference_tar_gz.simpleName/regions_chr1p.bed" &> ${participant_id}_run.log

    # Copy the internal log file from it’s expected location
    echo "Check BG"
    ls -l ${participant_id}.bg/
    echo "Check QC folder"
    ls -l ${participant_id}.bg/qc/

    # Copy the internal log file from it’s expected location
    cp ${participant_id}.bg/qc/create_log.txt  ${participant_id}.bg_qc_create_log.txt 
    
    # But has it failed?
    if grep -q "${params.biograph_error_msg}"; then
        echo "Biograph failed, exiting with exit status 1"
            exit 1
    else 
        echo "Biograph succeeded!"
    fi	
    
    if [ -d ${participant_id}.bg ]i; then
        if [ -f ${participant_id}.bg/analysis/results.vcf ]; then
            cp ${participant_id}.bg/analysis/results.vcf ${participant_type}_${participant_id}.vcf
        fi
        if [ -d ${participant_id}.bg/qc ]; then
            cp -R ${participant_id}.bg/qc/* ./
        fi
    fi
    """
  }

