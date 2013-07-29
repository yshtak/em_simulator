#!/bin/bash
TODAY=`date -d '' '+%Y_%m_%d'`
echo "Start"
bundle exec ruby 05_run.rb
sleep 1
bundle exec ruby merge.rb
zip result/result_$TODAY.zip result/*csv
rm result/*csv
echo "End"
#echo result_$TODAY.zip
