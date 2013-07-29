require './05_paticle_filter'
require 'awesome_print'
require '../config/simulation_data'

include SimulationData
config = { 
 chunk_size: 3,
 weather: SUNNY
}
pf = ParticleFilter.new config
#ap pf.ave_models
#ap pf.particles 
file = open('./oneday.csv','r')
solars = file.readline.split(',').map{|a| a.to_f}
(0..94).each{|time|
 pf.resample
 pf.predict solars[time], time
 pf.weight
 p pf.measure
}

