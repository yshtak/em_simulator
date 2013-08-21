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

## add HomeAgent to Actor
(0..4).to_a.each do |number|
 ha_id = "nagoya_#{number}"
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
 solarfile = open("#{DIRROOT}/data/solar/nagoya/#{number}_plus30.csv")
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

sim_day = SIM_DAYS

(0..4).each do |number|
 ha_id = "nagoya_#{number}" 
  output = open("./result/#{ha_id}/result_0.csv",'w')
  output.write("buy,battery,predict,real,sell,weather\n")
  number = 0 # 分割ナンバー
  for count in 1..sim_day do
   demands = agent_demands[number][count-1].split(',').map{|x| x.to_f}
   solars = agent_solars[number][count-1].split(',').map{|x| x.to_f}
   sum_solar = solars.inject(0.0){|x,sum|sum += x}
   
   print "Day #{count}, Sum Solar:#{sum_solar},"
   if sum_solar > SUNNY_BORDER
    print "Weather -> [Sunny]\n"
   elsif sum_solar > CLOUDY_BORDER
    print "Weather -> [Cloudy]\n"
   else
    print "Weather -> [Rainy]\n"
   end

   Celluloid::Actor[ha_id].switch_weather_for_pf sum_solar 
   Celluloid::Actor[ha_id].set_demands demands
   Celluloid::Actor[ha_id].set_solars solars 

   #buys, bats = ha.date_action
=begin
   output_datas = (0..4).map{|index|
    id = "nagoya_#{index}"
    Celluloid::Actor[id].future.data_action
   }
   output_datas.each_with_index{|future,index|
    p future
    simdatas = future.value # ひとつひとつの出力結果
    output = open("./result/#{index}/result_0.csv",'w')
    output.write("buy,battery,predict,real,sell,weather\n")
    (0..simdatas[:buy].size-1).each{|i|
      output.write "#{simdatas[:buy][i]},#{simdatas[:battery][i]},#{simdatas[:predict][i]},#{simdatas[:real][i]},#{simdatas[:sell][i]},#{simdatas[:weather]}\n"
    }
   }
=end
   simdatas = Celluloid::Actor[ha_id].date_action
   (0..simdatas[:buy].size-1).each{|i|
    output.write "#{simdatas[:buy][i]},#{simdatas[:battery][i]},#{simdatas[:predict][i]},#{simdatas[:real][i]},#{simdatas[:sell][i]},#{simdatas[:weather]}\n"
    #output.write "#{buys[i]},#{bats[i]}\n"
   }

   Celluloid::Actor[pca.id].day_action
   Celluloid::Actor[ha_id].init_date # 初期化
   Celluloid::Actor[pca.id].init_date # 初期化
    
   if count % 5 == 0
    output.close
    number += 1
    output = open("./result/#{ha_id}/result_#{number}.csv",'w')
    output.write("buy,battery,predict,real,sell,weather\n")
   end
   #bats.each{|bat| battery_output.write("#{bat}\n") }
   #buys.each{|buy| buy_output.write("#{buy}\n")}
  end
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
