DIRROOT = File.expand_path File.dirname __FILE__
require 'yaml'
require "#{DIRROOT}/agents/03_home_agent"
#require "#{DIRROOT}/filter/02_particle_filter"
require "#{DIRROOT}/filter/05_particle_filter"
#require "#{DIRROOT}/filter/04_particle_filter"
require "awesome_print"
require "#{DIRROOT}/config/simulation_data.rb"
#: 初期設定
include SimulationData
ha = HomeAgent.new({filter: 'pf',address:'nagoya'})
#ha = HomeAgent.new({filter: 'none',address:'nagoya'})
#ha = HomeAgent.new({filter: 'normal', address:'nagoya'})
#ap ha.filter.config

# 365日分のデータ
#buy_output = open('buy_result.csv','w')
#battery_output = open('battery_result.csv','w')
output = open('./result/result_0.csv','w')
output.write("buy,battery,predict,real,sell\n")
number = 0 # 分割ナンバー

solarfile = open("#{DIRROOT}/data/solar/nagoya/0.csv")
demandfile = open("#{DIRROOT}/data/demand/nagoya/0.csv")
demand_list = demandfile.readlines
solar_list = solarfile.readlines
sim_day = 20
for count in 1..sim_day do
 demands = demand_list[count-1].split(',').map{|x| x.to_f}
 solars = solar_list[count-1].split(',').map{|x| x.to_f}
 sum_solar = solars.inject(0.0){|x,sum|sum += x}
 
 print "Day #{count}, Sum Solar:#{sum_solar},"
 if sum_solar > 12000.0
  print "Weather: Sunny.\n"
  ha.select_weather SUNNY 
 elsif sum_solar > 5500.0
  ha.select_weather CLOUDY 
  print "Weather: Cloudy.\n"
 else
  ha.select_weather RAINY 
  print "Weather: Rain.\n"
 end

 ha.set_demands demands
 ha.set_solars solars 

 #buys, bats = ha.date_action
 simdatas = ha.date_action
 (0..simdatas[:buy].size-1).each{|i|
  output.write "#{simdatas[:buy][i]},#{simdatas[:battery][i]},#{simdatas[:predict][i]},#{simdatas[:real][i]},#{simdatas[:sell][i]}\n"
  #output.write "#{buys[i]},#{bats[i]}\n"
 }
 ha.init_date # 初期化

 if count % 5 == 0
  output.close
  number += 1
  output = open("./result/result_#{number}.csv",'w')
  output.write("buy,battery,predict,real,sell\n")
 end
 #bats.each{|bat| battery_output.write("#{bat}\n") }
 #buys.each{|buy| buy_output.write("#{buy}\n")}
end

#output.close
#battery_output.close
#buy_output.close

#test,bs = ha.date_action
#w = open('results.csv', "w")
#w.write test.join(',')
#w.write "\n"
#w.write bs.join(',')
#w.close
