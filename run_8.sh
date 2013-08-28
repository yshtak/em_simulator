#!/bin/bash
COUNT=$1
AREA=$2
TODAY=`date -d '' '+%Y_%m_%d'`
echo "Start"
bundle exec ruby 08_run.rb $COUNT
sleep 1
bundle exec ruby 02_merge.rb $COUNT $AREA
zip -r result/result_${TODAY}_${COUNT}.zip result/*csv result/${AREA}_${COUNT}_*
rm result/*csv
rm -rf result/${AREA}_${COUNT}_*
echo "End"
#echo result_$TODAY.zip
