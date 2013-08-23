# coding:utf-8
DIRROOT = File.expand_path File.dirname __FILE__
require 'yaml'
require 'celluloid/autostart'
require 'parallel'
require 'thread'
require "#{DIRROOT}/agents/07_home_agent"
require "#{DIRROOT}/filter/06_particle_filter"
require "awesome_print"
require "#{DIRROOT}/config/simulation_data.rb"
require "#{DIRROOT}/agents/01_power_company"
#: 初期設定
include SimulationData
pca = PowerCompany.new
Celluloid::Actor[pca.id] = pca
agent_demands = []
agent_solars = []

writers = {}
## add HomeAgent to Actor
(0..4).to_a.each do |number|
 ha_id = "nagoya_#{number}"
 writers.store(ha_id, open("./result/#{ha_id}/result_0.csv",'w'))
 writers[ha_id].write("buy,battery,predict,real,sell,weather\n")
 ha = HomeAgent.new({
   filter: 'pf',
   address:'nagoya', 
   midnight_strategy: true,
   contractor: Celluloid::Actor[pca.id],
   id: ha_id
 })
 #ha = HomeAgent.new({filter: 'pf',address:'nagoya', midnight_strategy: true,contractor: pca})
 Celluloid::Actor[ha.id] = ha
 Dir.mkdir("./result/#{ha_id}") if !File.exist?("./result/#{ha_id}") # 出力保存場所作成
 ## データの格納
 solarfile = open("#{DIRROOT}/data/solar/nagoya/0_plus30.csv")
 #solarfile = open("#{DIRROOT}/data/solar/nagoya/#{number}_plus30.csv")
 demandfile = open("#{DIRROOT}/data/demand/nagoya/#{number}.csv")
 demand_list = demandfile.readlines
 solar_list = solarfile.readlines
 # エージェントごとの需要と太陽光発電を格納
 agent_demands << demand_list
 agent_solars << solar_list 
end

#ha = HomeAgent.new({filter: 'none',address:'nagoya', midnight_strategy: true})
#ha = HomeAgent.new({filter: 'normal', address:'nagoya'})
#ap ha.filter.config

# 365日分のデータ
#buy_output = open('buy_result.csv','w')
#battery_output = open('battery_result.csv','w')
#output = open('./result/nagoya_0/result_0.csv','w')
#output.write("buy,battery,predict,real,sell,weather\n")
#number = 0 # 分割ナンバー
number = 0
sim_day = SIM_DAYS
agent_num = 1

for count in 1..sim_day do
  #output = open("./result/#{ha_id}/result_0.csv",'w')
  #output.write("buy,battery,predict,real,sell,weather\n")
  #number = 0 # 分割ナンバー
  simdatas = []
  solars = agent_solars[0][count-1].split(',').map{|x| x.to_f}
  sum_solar = solars.inject(0.0){|x,sum|sum += x}
  Celluloid::Actor[pca.id].switch_weather sum_solar
  print "Day #{count}, "
  if sum_solar > SUNNY_BORDER
    print "Weather -> [Sunny]\n"
  elsif sum_solar > CLOUDY_BORDER
    print "Weather -> [Cloudy]\n"
  else
    print "Weather -> [Rainy]\n"
  end

  (0..agent_num-1).each{|index|
    ha_id = "nagoya_#{index}"
    demands = agent_demands[index][count-1].split(',').map{|x| x.to_f}
    #solars = agent_solars[index][count-1].split(',').map{|x| x.to_f}
    #sum_solar = solars.inject(0.0){|x,sum|sum += x}
    Celluloid::Actor[ha_id].switch_weather_for_pf sum_solar 
    Celluloid::Actor[ha_id].set_demands demands
    Celluloid::Actor[ha_id].set_solars solars 
     #print "Day #{count}, Sum Solar:#{sum_solar},"
  }

  (0..60*24/TIMESTEP-1).each{|time|
   (0..agent_num-1).to_a.each do |agentid|
     ha_id = "nagoya_#{agentid}"
     simdatas = Celluloid::Actor[ha_id].onestep_action time
     (0..simdatas[:buy].size-1).each{|i|
      writers[ha_id].write "#{simdatas[:buy][i]},#{simdatas[:battery][i]},#{simdatas[:predict][i]},#{simdatas[:real][i]},#{simdatas[:sell][i]},#{simdatas[:weather]}\n"
      #output.write "#{buys[i]},#{bats[i]}\n"
     }
   end
   Celluloid::Actor[pca.id].onestep_action time
  }
 (0..agent_num-1).each{|index|
   id = "nagoya_#{index}"
   if count % 5 == 0
      writers[id].close
      number += 1
      writers[id] = open("./result/#{id}/result_#{number}.csv",'w')
      writers[id].write("buy,battery,predict,real,sell,weather\n")
   end
   Celluloid::Actor[id].init_date # 初期化
 }
 Celluloid::Actor[pca.id].csv_out("./result/pca_#{count}.csv") if count % 5 == 0
 Celluloid::Actor[pca.id].init_date # 初期化
end
   #bats.each{|bat| battery_output.write("#{bat}\n") }
   #buys.each{|buy| buy_output.write("#{buy}\n")}
#output.close
#battery_output.close
#buy_output.close

#test,bs = ha.date_action
#w = open('results.csv', "w")
#w.write test.join(',')
#w.write "\n"
#w.write bs.join(',')
#w.close
