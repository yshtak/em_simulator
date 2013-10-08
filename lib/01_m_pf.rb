##
# Memory Based Particle Filter
#
require "#{File.expand_path File.dirname __FILE__}/../config/simulation_data"
require "#{File.expand_path File.dirname __FILE__}/../lib/particle"
require 'awesome_print'

class MParticleFilter
  include SimulationData
  def initialize cfg={}
    cfg = {
      timestep: 96,
      current_time: 0,
      particle: 1000
    }.merge(cfg)

    @step = cfg[:timestep]
    @time = cfg[:current_time]
    ## 過去の履歴
    @history = {
      SUNNY => [],
      RAINY => [],
      CLOUDY => []
    }
    # パーティクルの初期化
    @particles = Array.new(cfg[:particle], Particle.new(0.0, 1.0))
  end

  def estimate
  end

  def resampling
  end

  private

  # 過去の履歴を追跡して似たものを解析する
  def trace_similar_history
  end

end
