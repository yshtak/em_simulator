require 'csv'
require 'matrix'
require './config/simulation_data'

include SimulationData
#output = open("./result/merge.csv",'w')
count = 0
mape = 0.0
mad = 0.0
msd = 0.0
eps = 0.0
ave = 0.0
sim_day = SIM_DAYS
NUMBER=ARGV[0] # Agent Number
AREA=ARGV[1] # Area

(0..AGENT_NUM-1).each do |agentid|
  CSV.open("./result/#{AREA}_#{NUMBER}_#{agentid}/merge.csv",'w') do |writer|
   header = ["Buy","Battery","Predict","Real","Sell","Weather","Demand"]
   col_size = header.size
   writer << header
   (0..sim_day/10-1).each{|num|
    file = open("./result/#{AREA}_#{NUMBER}_#{agentid}/result_#{(num+1)*10}.csv")
    tmp_result = []
    file.each do |line|
     if count != 0
      tmp_result << Vector.elements(line.split(',').map{|x|x.to_f})
      #p tmp_result.size
     end
     count += 1
     if tmp_result.size == 96
      onedata = tmp_result.inject(Vector.elements Array.new(col_size,0)){|sum, x| sum += x} / 96.0

      writer << (onedata).to_a
      tmp_result = []
     end
     #writer << line.split(',').map{|x| x.to_f}
    end
   }
  end
end
##
count = 0 # カウントの初期化
(0..AGENT_NUM-1).each do |agentid|
  CSV.open("./result/#{AREA}_#{NUMBER}_#{agentid}/sum.csv",'w') do |writer|
   header = ["BuySum","SellSum","BatteryAverage"]
   col_size = header.size
   writer << header
   (0..sim_day/10-1).each{|num|
    file = open("./result/#{AREA}_#{NUMBER}_#{agentid}/result_#{(num+1)*10}.csv",'r')
    tmp_result = []
    file.each do |line|
     datas = line.split(',').map{|x|x.to_f}
     if count != 0
      tmp_result << Vector.elements([datas[0],datas[4],datas[1]])
     end
     count += 1
     if tmp_result.size == 96
      onedata = tmp_result.inject(Vector.elements Array.new(col_size,0)){|sum,x| sum+= x}.to_a
      onedata[2] /= 96.0 
      writer << (onedata)
      tmp_result = []
     end
    end
   }
  end
end
##
count = 0
CSV.open("./result/pca_sum.csv","w").each do |writer|
  header = ["sell","buy","purchase_price","sell_price","outcome"]
  col_size = header.size
  writer << header
  (0..sim_day/10-1).each{|num|
    file = open("./result/pca_#{num+1}*10.csv",'r')
    tmp = []
    file.each do |line|
      data = line.split(',').map{|x|x.to_f}
      if count != 0
        tmp << Vector.elements([data[0],data[1],data[2],data[3],(data[0]*data[3] - data[1]*data[2])])
      end
      count += 1
      if tmp.size == 96
        onedata = tmp.inject(Vector.elements Array.new(col_size,0)){|sum,x| sum+=x}.to_a
        #onedata[2] /= 96
        writer << onedata
        tmp = []
      end
    end
  }
end
# mapeの計算
(0..AGENT_NUM-1).each do |agentid|
  predicts = []
  reals = []
  (0..sim_day/10-1).each{|num|
   file = open("./result/#{AREA}_#{NUMBER}_#{agentid}/result_#{(num+1)*10}.csv","r")
   file.each do |line|
    data = line.split(",")
    predicts << data[2].to_f # Predict Value
    reals << data[3].to_f # Real value
   end
  }
  ave = reals.inject(0.0){|acc, data| acc += data}/reals.size
  mape = (0..reals.size-1).inject(0.0){|acc, index| (reals[index] + 1.0 - predicts[index]).abs / (reals[index] + 1.0)} / reals.size
  p mape * 100
end
#output.close
