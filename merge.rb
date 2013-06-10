require 'csv'
require 'matrix'
#output = open("./result/merge.csv",'w')
count = 0
mape = 0.0
mad = 0.0
msd = 0.0
eps = 0.0
ave = 0.0

CSV.open("./result/merge.csv",'w') do |writer|
 writer << ["Buy","Battery","Predict","Real"]
 (0..365/5-1).each{|num|
 file = open("./result/result_#{num}.csv")
 tmp_result = []

 file.each do |line|
  count += 1
  tmp_result << Vector.elements(line.split(',').map{|x|x.to_f})
  if count > 95
   #p tmp_result
   onedata = tmp_result.inject(Vector.elements Array.new(4,0)){|x,sum| sum += x} / 96.0
   writer << (onedata).to_a
   count = 0
   tmp_result = []
  end
  #writer << line.split(',').map{|x| x.to_f}
 end
 }
end

predicts = []
reals = []
(0..365/5-1).each{|num|
 file = open("./result/result_#{num}.csv","r")
 file.each do |line|
  data = line.split(",")
  predicts << data[2].to_f # Predict Value
  reals << data[3].to_f # Real value
 end
}
ave = reals.inject(0.0){|acc, data| acc += data}/reals.size
mape = (0..reals.size-1).inject(0.0){|acc, index| (reals[index] + 1.0 - predicts[index]).abs / (reals[index] + 1.0)} / reals.size
p mape * 100
#output.close
