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
    .splitCsv(skip:1)
    .map {sample_name, file_path -> [ sample_name, file_path ] }
    .set { ch_input }

// Define Process
process step_1 {
    tag "$sample_name"
    label 'low_memory'
    publishDir "${params.outdir}", mode: 'copy'

    input:
    set val(sample_name), file(input_file) from ch_input

    output:
    file "input_file_head.txt" into ch_out

    script:
    """
    head $input_file > input_file_head.txt
    """
  }

process report {
    publishDir "${params.outdir}/MultiQC", mode: 'copy'

    input:
    file (table) from ch_out
    
    output:
    file "multiqc_report.html" into ch_multiqc_report

    script:
    """
    cp -r ${params.report_dir}/* .
    Rscript -e "rmarkdown::render('report.Rmd',params = list(res_table='$table'))"
    mv report.html multiqc_report.html
    """
}