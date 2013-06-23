require 'awesome_print'
require 'bunny'
require 'celluloid'
require './lib/moppy.rb'

# ホームエージェントクラス
# 
class HomeAgent < Moppy
 include Celluloid
 include Celluloid::Logger

 def initializer cfg
  # Set the Configuration
  @config = {
   timestep: 15,
   filter: 'none', 
  }.merge(cfg)

 end



 private
 

end
