#!/bin/bash
COUNT=$1
AREA=$2
TODAY=`date -d '' '+%Y_%m_%d_'`+$COUNT
echo "Start"
bundle exec ruby 07_run.rb $COUNT
sleep 1
bundle exec ruby 02_merge.rb $COUNT $AREA
zip -r result/result_$TODAY_$COUNT.zip result/*csv result/${AREA}_${COUNT}_*
rm result/*csv
rm -rf result/${AREA}_${COUNT}_*
echo "End"
#echo result_$TODAY.zip
