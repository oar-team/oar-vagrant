#!/bin/bash
for i in {0..3}; do
    nvidia-smi -i $i -mig 1
    nvidia-smi mig -i $i -cgi 19,1g.5gb -C
    nvidia-smi mig -i $i -cgi 19,1g.5gb -C
    nvidia-smi mig -i $i -cgi 19,1g.5gb -C
    nvidia-smi mig -i $i -cgi 19,1g.5gb -C
done


T=( $(ls /dev/nvidia-caps/* | grep -v -e nvidia-cap[1,2]$ ) )
j=0
for i in {1..64}; do
    if (( (i+1)/2  % 8 )); then
        m="YES"
        g="/dev/nvidia$(((i-1) / 16)) ${T[j]} ${T[$((j+1))]}"
        if (((i-1) % 2)); then
            ((j+=2));
        fi
    else
        m="NO"
        g=""
    fi
    ssh server oarnodesetting -r $i -p gpudevice="$g" -p has_gpu="$m"
done
