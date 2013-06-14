=begin
require './02_particle_filter'

pf = ParticleFilter.new
datas = []
open('./oneday.csv','r').each{|line|
 datas = line.split(",").map{|m| m.to_f}
}
datas.each do |data|
 pf.next_value_predict data
end
=end

require "./02_particle_filter"

#datas = (open("oneday.csv","r").inject(""){|str,line| str + line.chomp}).split(",").map{|a| a.to_i}

#datas.inject(0){|sum,data| print "[#{sum}]:#{data}"; sum += 1}
#puts ""

#datas = []
#open("oneday.txt",'r').each {|line| datas << line.chop.to_i}


datas = open("oneday.csv","r").read.split(",").map{|x| x.to_f}
#datas = open("oneday2.csv","r").read.split(",").map{|x| x.to_f}
#datas = open("oneday.csv","r").read.split(",").map{|x| x.to_f}
#datas = open("sunny.csv","r").read.split(",").map{|x| x.to_f}
#datas = open("cloudy.csv","r").read.split(",").map{|x| x.to_f}
#datas = open("rainny.csv","r").read.split(",").map{|x| x.to_f}
#mdata = open("rainny.csv","r").read.split(",").map{|x| x.to_f}
#mdata = open("cloudy.csv","r").read.split(",").map{|x| x.to_f}
mdata = open("sunny.csv","r").read.split(",").map{|x| x.to_f}

mean = datas.inject(0){|sum,d| sum += d} / datas.size
sigma = datas.inject(0){|sum, d| sum += d*d} / (datas.size - 1)
config = {model_data: mdata}
pf = ParticleFilter.new config
pf.set_weather("sunny")
#pf = ParticleFilter.new config

file = open('test_result.csv', 'w')
file.write("RealData,PredictData\n")
datas.each_with_index do |data, index|
 value = pf.next_value_predict data, index
 #p "[#{index}]:#{value}"
 #print value, ": pre_value #{data}\n"
 print value, "\n"
 file.write("#{data},#{value}\n")
end 
file.close
