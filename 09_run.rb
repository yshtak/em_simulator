# coding:utf-8
DIRROOT = File.expand_path File.dirname __FILE__
require 'yaml'
require 'celluloid/autostart'
require 'parallel'
require 'thread'
require "#{DIRROOT}/agents/09_home_agent"
require "#{DIRROOT}/filter/06_particle_filter"
require "awesome_print"
require "#{DIRROOT}/config/simulation_data.rb"
require "#{DIRROOT}/agents/01_power_company"
#: 初期設定
include SimulationData
PID_NUMBER= ARGV[0].nil? ? 0 : ARGV[0]
AREA= ARGV[1].nil? ? "nagoya" : ARGV[1]
pca = PowerCompany.new
Celluloid::Actor[pca.id] = pca
agent_demands = []
agent_solars = []
agent_num = 3

## デマンド及び太陽光のデータを繰り返し使い続ける
def loop_index size, time
  return time > size - 1 ? time % size : time 
end

writers = {}
bb = [0.65,1.0,2.0]
buy_targets = [0.3,0.4,0.4]
sell_targets = [0.4,0.5,0.4]

## add HomeAgent to Actor
(0..agent_num-1).to_a.each do |number|
 ha_id = "#{AREA}_#{PID_NUMBER}_#{number}"
 Dir.mkdir("./result/#{ha_id}") if !File.exist?("./result/#{ha_id}") # 出力保存場所作成
 #writers.store(ha_id, open("./result/#{ha_id}/result_0.csv",'w'))
 #writers[ha_id].write("buy,battery,predict,real,sell,weather,demand\n")
 ha = HomeAgent.new({
   filter: 'pf',
   address: AREA, 
   midnight_strategy: true,
   max_strage: 5000.0 * bb[number], # 蓄電容量(Wh)
   buy_target: buy_targets[number],
   sell_target: sell_targets[number],
   contractor: Celluloid::Actor[pca.id],
   id: ha_id
 })
 #ha = HomeAgent.new({filter: 'pf',address:'#{AREA}', midnight_strategy: true,contractor: pca})
 Celluloid::Actor[ha.id] = ha
 ## データの格納
 solarfile = open("#{DIRROOT}/data/solar/#{AREA}/0_10days.csv") ## 10日間繰り返し
 #solarfile = open("#{DIRROOT}/data/solar/#{AREA}/0_plus30.csv") ## 395日(最初の30日は捨てる)
 demandfile = open("#{DIRROOT}/data/demand/#{AREA}/#{number}.csv")
 demand_list = demandfile.readlines
 solar_list = solarfile.readlines
 # エージェントごとの需要と太陽光発電を格納
 agent_demands << demand_list
 agent_solars << solar_list 
end

#ha = HomeAgent.new({filter: 'none',address:'#{AREA}', midnight_strategy: true})
#ha = HomeAgent.new({filter: 'normal', address:'#{AREA}'})
#ap ha.filter.config

# 365日分のデータ
#buy_output = open('buy_result.csv','w')
#battery_output = open('battery_result.csv','w')
#output = open('./result/#{AREA}_0/result_0.csv','w')
#output.write("buy,battery,predict,real,sell,weather\n")
#number = 0 # 分割ナンバー
number = 0
sim_day = SIM_DAYS

#start_index = rand(320) ## ランダムでいつのdemand及びソーラのデータを取得するか決める
start_index = 0
for count in 1..sim_day do
  #output = open("./result/#{ha_id}/result_0.csv",'w')
  #output.write("buy,battery,predict,real,sell,weather\n")
  #number = 0 # 分割ナンバー
  simdatas = []
  solars = agent_solars[0][loop_index(agent_solars[0].size, start_index+count-1)].split(',').map{|x| x.to_f}
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
    ha_id = "#{AREA}_#{PID_NUMBER}_#{index}"
    demands = agent_demands[index][loop_index(agent_demands[index].size, start_index+count-1)].split(',').map{|x| x.to_f}
    #solars = agent_solars[index][count-1].split(',').map{|x| x.to_f}
    #sum_solar = solars.inject(0.0){|x,sum|sum += x}
    #
    Celluloid::Actor[ha_id].switch_weather_for_pf sum_solar 
    Celluloid::Actor[ha_id].day_start_action ## 一日刻みの行動開始
    Celluloid::Actor[ha_id].set_demands demands
    Celluloid::Actor[ha_id].set_solars solars 
    #
     #print "Day #{count}, Sum Solar:#{sum_solar},"
  }

  (0..60*24/TIMESTEP-1).each{|time|
   (0..agent_num-1).to_a.each do |agentid|
     ha_id = "#{AREA}_#{PID_NUMBER}_#{agentid}"
     Celluloid::Actor[ha_id].onestep_action time
     
     #(0..simdatas[:buy].size-1).each{|i|
      #writers[ha_id].write "#{simdatas[:buy][i]},#{simdatas[:battery][i]},#{simdatas[:predict][i]},#{simdatas[:real][i]},#{simdatas[:sell][i]},#{simdatas[:weather]},#{simdatas[:demand][i]}\n"
      #output.write "#{buys[i]},#{bats[i]}\n"
     #}
   end

   Celluloid::Actor[pca.id].onestep_action time
   #
  }
  #number += 1 if count % 10 == 0 ### 全体の出力ファイルのナンバリング
  #(0..agent_num-1).each{|index|
  # id = "#{AREA}_#{PID_NUMBER}_#{index}"
  # if count % 10 == 0
  #    writers[id].close
  #    writers[id] = open("./result/#{id}/result_#{number}.csv",'w')
  #    writers[id].write("buy,battery,predict,real,sell,weather,demand\n")
  # end
  # Celluloid::Actor[id].init_date
  #}
 (0..agent_num-1).each{|index| 
   id = "#{AREA}_#{PID_NUMBER}_#{index}"
   Celluloid::Actor[id].init_date
 }# 初期化
 Celluloid::Actor[pca.id].csv_out("./result/pca_#{count}.csv") if count % 10 == 0
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

