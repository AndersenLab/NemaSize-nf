
workflow {
    ch_data = channel.value(file(params.data_f, checkIfExists: true))
    ch_slurm_temp = channel.fromPath(params.slurm_temp, checkIfExists: true)
    ch_project_name = ch_data.map { it.baseName }
    ch_email = channel.of(params.email)

    create_slurm(ch_project_name, ch_email, ch_slurm_temp)
    transfer_data(ch_data, create_slurm.out)
    start_job(transfer_data.out.last())
    create_script_for_transfer_results(ch_project_name, ch_data)
}



process create_slurm {
    input:
        val project_name
        val email
        path slurm_temp
    output:
        path "slurm_${project_name}.sh"
    script:
        """
        cp ${slurm_temp} slurm_${project_name}.sh
        sed -i "s/JOB_NAME/${project_name}/g" slurm_${project_name}.sh
        sed -i "s/OUTPUT_NAME/${project_name}/g" slurm_${project_name}.sh
        sed -i "s/DATA_FOLDER/${project_name}/g" slurm_${project_name}.sh
        sed -i "s/EMAIL/${email}/g" slurm_${project_name}.sh
        """
}


process transfer_data {
    input:
        path data
        path slurm_script
    output:
        val "/scratch/eande106/NemaSize/${data.baseName}/${slurm_script.name}"
    script:
        """
        ssh -i ~/.ssh/id_rsaNemaSize zli435@dsailogin.arch.jhu.edu "mkdir -p /scratch/eande106/NemaSize/${data.baseName}"
        scp -i ~/.ssh/id_rsaNemaSize -r ${data}/raw_images zli435@dsailogin.arch.jhu.edu:/scratch/eande106/NemaSize/${data.baseName}/
        scp -i ~/.ssh/id_rsaNemaSize -r ${slurm_script} zli435@dsailogin.arch.jhu.edu:/scratch/eande106/NemaSize/${data.baseName}
        echo "finish"
        """
}

process start_job {
    input:
        val script_name
    output:
        stdout
    script:
        """
        ssh -i ~/.ssh/id_rsaNemaSize zli435@dsailogin.arch.jhu.edu "mkdir -p \$(dirname ${script_name})/NemaSize_output && sbatch ${script_name}"
        echo "job started"
        """
}



process create_script_for_transfer_results {
    input:
        val project_name
        val data
    output:
        stdout
    script:
        """
        echo '#!/bin/bash' > ${data}/transfer_results.sh
        echo 'set -e' >> ${data}/transfer_results.sh
        echo 'rm -rf ${data}/NemaSize_output' >> ${data}/transfer_results.sh
        echo 'scp -i ~/.ssh/id_rsaNemaSize -r zli435@dsailogin.arch.jhu.edu:/scratch/eande106/NemaSize/${project_name}/NemaSize_output ${data}/' >> ${data}/transfer_results.sh
        echo 'ssh -i ~/.ssh/id_rsaNemaSize zli435@dsailogin.arch.jhu.edu "rm -rf /scratch/eande106/NemaSize/${project_name}"' >> ${data}/transfer_results.sh
        echo 'echo "Analysis results transferred successfully."' >> ${data}/transfer_results.sh
        chmod +x ${data}/transfer_results.sh

        echo "Script to transfer results created at ${data}/transfer_results.sh"
        """
}

