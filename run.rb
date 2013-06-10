DIRROOT = File.expand_path File.dirname __FILE__
require 'yaml'
require "#{DIRROOT}/agents/home_agent"
require "#{DIRROOT}/filter/02_particle_filter"

#: 初期設定

ha = HomeAgent.new({filter: 'pf',address:'nagoya'})
#ha = HomeAgent.new({filter: 'none',address:'nagoya'})

# 365日分のデータ
#buy_output = open('buy_result.csv','w')
#battery_output = open('battery_result.csv','w')
output = open('./result/result_0.csv','w')
number = 0

solarfile = open("#{DIRROOT}/data/solar/nagoya/0.csv")
demandfile = open("#{DIRROOT}/data/demand/nagoya/0.csv")
demand_list = demandfile.readlines
solar_list = solarfile.readlines

for count in 1..365 do
 demands = demand_list[count-1].split(',').map{|x| x.to_f}
 solars = solar_list[count-1].split(',').map{|x| x.to_f}
 sum_solar = solars.inject(0.0){|x,sum|sum += x}
 
 print "Day #{count}, Sum Solar:#{sum_solar},"
 if sum_solar > 12000.0
  print "Weather: Sunny.\n"
  ha.select_weather 'sunny'
 elsif sum_solar > 5500.0
  ha.select_weather 'cloudy'
  print "Weather: Cloudy.\n"
 else
  ha.select_weather 'rainny'
  print "Weather: Rain.\n"
 end

 ha.set_demands demands
 ha.set_solars solars 

 #buys, bats = ha.date_action
 simdatas = ha.date_action
 (0..simdatas[:buy].size-1).each{|i|
  output.write "#{simdatas[:buy][i]},#{simdatas[:battery][i]},#{simdatas[:predict][i]},#{simdatas[:real][i]}\n"
  #output.write "#{buys[i]},#{bats[i]}\n"
 }
 ha.init_date # 初期化

 if count % 5 == 0
  output.close
  number += 1
  output = open("./result/result_#{number}.csv",'w') if count!=365
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
