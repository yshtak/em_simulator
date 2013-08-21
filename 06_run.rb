# coding:utf-8
DIRROOT = File.expand_path File.dirname __FILE__
require 'yaml'
require 'celluloid/autostart'
require 'thread'
require "#{DIRROOT}/agents/06_home_agent"
require "#{DIRROOT}/filter/06_particle_filter"
require "awesome_print"
require "#{DIRROOT}/config/simulation_data.rb"
require "#{DIRROOT}/agents/01_power_company"
#: 初期設定
include SimulationData
pca = PowerCompany.new
ha = HomeAgent.new({filter: 'pf',address:'nagoya', midnight_strategy: true,contractor: pca})

Celluloid::Actor[pca.id] = pca
Celluloid::Actor[pca.id].dump
#ha = HomeAgent.new({filter: 'none',address:'nagoya', midnight_strategy: true})
#ha = HomeAgent.new({filter: 'normal', address:'nagoya'})
#ap ha.filter.config

# 365日分のデータ
#buy_output = open('buy_result.csv','w')
#battery_output = open('battery_result.csv','w')
output = open('./result/result_0.csv','w')
output.write("buy,battery,predict,real,sell,weather\n")
number = 0 # 分割ナンバー

solarfile = open("#{DIRROOT}/data/solar/nagoya/0_plus30.csv")
demandfile = open("#{DIRROOT}/data/demand/nagoya/0.csv")
demand_list = demandfile.readlines
solar_list = solarfile.readlines
sim_day = SIM_DAYS


for count in 1..sim_day do
 demands = demand_list[count-1].split(',').map{|x| x.to_f}
 solars = solar_list[count-1].split(',').map{|x| x.to_f}
 sum_solar = solars.inject(0.0){|x,sum|sum += x}
 
 print "Day #{count}, Sum Solar:#{sum_solar},"

 if sum_solar > SUNNY_BORDER
  print "Weather -> [Sunny]\n"
 elsif sum_solar > CLOUDY_BORDER
  print "Weather -> [Cloudy]\n"
 else
  print "Weather -> [Rainy]\n"
 end

 ha.switch_weather_for_pf sum_solar 
 ha.set_demands demands
 ha.set_solars solars 

 #buys, bats = ha.date_action
 simdatas = ha.date_action
 (0..simdatas[:buy].size-1).each{|i|
  output.write "#{simdatas[:buy][i]},#{simdatas[:battery][i]},#{simdatas[:predict][i]},#{simdatas[:real][i]},#{simdatas[:sell][i]},#{simdatas[:weather]}\n"
  #output.write "#{buys[i]},#{bats[i]}\n"
 }
 ha.init_date # 初期化

 if count % 5 == 0
  output.close
  number += 1
  output = open("./result/result_#{number}.csv",'w')
  output.write("buy,battery,predict,real,sell,weather\n")
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
