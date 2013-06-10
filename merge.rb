require 'csv'
require 'matrix'
#output = open("./result/merge.csv",'w')
count = 0
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
#output.close
