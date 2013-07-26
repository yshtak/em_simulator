require './05_paticle_filter'
require 'awesome_print'
require '../config/simulation_data'

include SimulationData
config = { 
 chunk_size: 3,
 weather: SUNNY
}
pf = ParticleFilter.new config

ap pf.weather
pf.resample

#ap pf.ave_models
#ap pf.particles 

