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
    set file("${participant_id}.bg/*"), file("mock_${participant_id}.*"), file("*.txt") into ch_out
    file "*.vcf.gz" into ch_out_vcf

    script:
    def regions_bed = params.bedfile != 'NO_FILE' ? "--bed $reference_tar_gz.simpleName/${params.bedfile}" : ''
    """
    ls -l
    echo `date` "participant_id:" $participant_id
    echo `date` "participant_type:" $participant_type
    touch mock_${participant_id}.txt
    touch mock_${participant_id}.vcf
    echo `date` "Finished mock file touch"

    mkdir -p tmp
    echo `date` "Start reference unzip"
    if [ ! -d $reference_tar_gz.simpleName ]; then
        tar xvfz $reference_tar_gz
    fi
    echo `date` "Finished expanding tarball"
    biograph license

    echo `date` "Starting BG full pipeline"
    biograph full_pipeline --biograph ${participant_id}.bg --ref $reference_tar_gz.simpleName \
    --reads $bam \
    --model /app/biograph_model.ml \
    --tmp ./tmp \
    --threads ${task.cpus} \
    --create "--max-mem 100 --format bam" \
    --discovery "${regions_bed}"

    if [ -d ${participant_id}.bg ]; then
        # Copy the internal log file from it’s expected location
        echo `date` "Check BG"
        ls -l ${participant_id}.bg/
        # Copy the internal log file from it’s expected location
        # cp ${participant_id}.bg/qc/create_log.txt  ${participant_id}.bg_qc_create_log.txt 
    fi
    
    # But has it failed?
    if grep -q "${params.biograph_error_msg}"; then
        echo `date` "Biograph failed, exiting with exit status 1"
        exit 1
    else 
        echo "Biograph succeeded!"
    fi	
    
    if [ -d ${participant_id}.bg ]; then
        ls -lhtr ${participant_id}.bg/analysis
        echo `date` "Check QC folder"
        ls -l ${participant_id}.bg/qc/

        if [ -f ${participant_id}.bg/analysis/results.vcf.gz ]; then
            cp ${participant_id}.bg/analysis/results.vcf.gz ${participant_type}_${participant_id}.vcf.gz
        fi
    fi
    echo `date` "Complete."
    """
  }

process list_files {
    tag "$participant_id"
    beforeScript 'eval "$(aws ecr get-login --registry-ids 084957857030 --no-include-email --region eu-west-2)" && docker pull 084957857030.dkr.ecr.eu-west-2.amazonaws.com/releases:biograph-6.0.5'

    input:
    set file(biograph_folder), file(mock_files), file(text_files) from ch_out.collect()
    file(vcf_files) from ch_out_vcf

    script:
    """
    ls -l
    cat ${biograph_folder}/qc/create_log.txt
    echo `date` "Complete."
    """
}
