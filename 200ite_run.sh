#!/bin/bash
nohup ./run_7_200ite.sh 1 nagoya > nohup_1.out &
sleep 1
nohup ./run_7_200ite.sh 2 nagoya > nohup_2.out &
sleep 1
nohup ./run_7_200ite.sh 3 nagoya > nohup_3.out &
sleep 1
nohup ./run_7_200ite.sh 4 nagoya > nohup_4.out &
sleep 1
nohup ./run_7_200ite.sh 5 nagoya > nohup_5.out &
