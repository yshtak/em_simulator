#!/bin/bash
COUNT=$1
TODAY=`date -d '' '+%Y_%m_%d_'`+$COUNT
echo "Start"
bundle exec ruby 07_run.rb
sleep 1
bundle exec ruby merge.rb
zip result/result_$TODAY_$COUNT.zip result/*csv
rm result/*csv
echo "End"
#echo result_$TODAY.zip
