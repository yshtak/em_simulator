require 'pry'
require 'awesome_print'
require "#{File.expand_path File.dirname __FILE__}/../config/simulation_data"
require "#{File.expand_path File.dirname __FILE__}/../lib/particle"
###################################################################
#
#=ParticleFilter
# 1変数専用のパーティクルフィルタ
#
# 2013-07-26
#
##################################################################
class ParticleFilter
 include SimulationData
 include Particle
 PARTICLE_NUM=1000
 STEP=10

 attr_accessor :particles, :chunk_size, :ave_models, :weather

 def initialize cfg={}
  config = {
   chunk_size: 5,
   weather: SUNNY
  }.merge(cfg)

  @particles = Array.new(PARTICLE_NUM) # 粒子
  @particles.map!{|x| Particle.new}
  @chunk_size = config[:chunk_size] ## 学習日数
  @next_true_value = Particle.new # 次の状態方程式に沿った値
  @ave_models = {} ## 平均的モデル
  @system_variance = 5.0 # 実験的に求める
  init_ave_model
  @bm = RandomBoxMuller.new # Random生成器（正規乱数）

  @state_eq = -> (x, dist, season_value,rnd){ x + dist + season_value + rnd }

  @trains = { # 学習データ
   SUNNY => Array.new(1440*@chunk_size/TIMESTEP, 0.0),
   CLOUDY => Array.new(1440*@chunk_size/TIMESTEP, 0.0),
   RAINY => Array.new(1440*@chunk_size/TIMESTEP, 0.0),
   TEMP => Array.new(1440/TIMESTEP, 0.0)
  }
  @weather = config[:weather]
 end
 ###以下パーティクルのアルゴリズム#################################

 #== リサンプリング関数
 # 第一ステップ．リサンプリング方法は遺伝アルゴリズムのエリート選択によって行う（多分）
 #
 # - @particles: パーティクル
 # - urnd: 正規乱数配列
 # TODO: 正規乱数を組み込むこと
 def resample
  @particles.each_with_index{|particle, index| particle.weight = Random::rand(2.0); particle.value = index }
  # 累積重みの計算
  weights = Array.new(@particles.size, 0.0)
  weights[0] = @particles[0].weight
  for index in 1..weights.size-1 do
   weights[index] = weights[index-1] + @particles[index].weight
  end 
  # 重みを基準にパーティクルをリサンプリングして重みを1.0に(エリート選択)
  tmp_particles = @particles.clone
  for index in 0..@particles.size-1 do
   w = Random::rand(1.0) * weights[weights.size - 1] # Randを入れる(正規乱数に修正すること)
   n = 0 # 
   while weights[n] < w do 
    n += 1 # nのインクリメント
   end
   @particles[index] = tmp_particles[n].clone # リサンプル(ちゃんとcloneする)
   @particles[index].weight = 1.0
  end
  return true
 end

 #== 推定関数
 # 第二ステップ，パーティクルフィルタの推定フェーズ
 # ここで状態方程式を定義する
 #
 # - @particles: パーティクル
 # - solar_t1: 現在時刻の太陽光発電量
 # - x: 粒子または実測値の値
 # - t1:
 # - return: bool
 # TODO: 正規乱数 
 def predict t1 
  xmodel_t2 = @ave_models[@weather][t1+1] # 時刻t1+1のモデルデータ
  xmodel_t1 = @ave_models[@weather][t1] # 時刻t1のモデルデータ
  #xmodel_t2 = @trains[@weather][t1+1] # 時刻t1+1のモデルデータ
  #xmodel_t1 = @trains[@weather][t1] # 時刻t1のモデルデータ
  season_value = (average_train_power(t1) - solar_t1 + average_train_power(t1 + 1) \
                  - xmodel_t2) / 1.0 # 季節変動変数 
  
  # 状態方程式を割り当てる
  for i in 0..@particles.size-1 do
   # 状態遷移
   @particles[i].value = @state_eq.call(@particles[i].value, (xmodel_t2 - xmodel_t2), season_value, Random::rand(-1.0..1.0)*@system_variance)
   #@particles[i].value += (xmodel_t2 - xmodel_t2) + season_value + Random::rand(-1.0..1.0)
  end
  return true 
 end

 #== 重み付け関数（尤度計算関数）
 # - x: パーティクル
 # - return: 尤度
 def likelihood particle
  ## 平均的なモデル及び最近のデータのモデルを利用
  # 観測地点
  obs = [-20,0,20]
  sum = 0.0
  variance = 20.0
  obs.each do |point|
   y = particle.value - point + Random::rand(1.0) * variance
   sum += Math.sqrt((@next_true_value - y)**2)
  end
  return sum/3.0
 end

 #== 重みの決定づけ関数
 # - @particles: 重み 
 # - ws:
 # - return: bool 
 def weight ws
  sum_weight = 0.0
  # 尤度に従いパーティクルの重みを決定する
  for i in 0..@particles.size-1 do
   @particles[i].weight = likelihood @particles[i]
   sum_weight += @particles[i].weight
  end
  # 重みの正規化
  for i in 0..@particles.size-1 do
   @particles[i].weight = (@particles[i].weight / sum_weight) * @particles.size
  end
  return true
 end

 #== 全パーティクルの重み付き平均を現状として観測する関数
 # - particles:
 # - result_particle: 結果 
 # - return: Bool
 def measure result_particle
  value = 0.0
  weight = 0.0
  for i in 0..@particles.size-1 do
   value += @particles[i].value * @particles[i].weight
   weight += @particles[i].weight
  end
  result_particle.value = value/weight 
  result_particle.weight = 1.0 # 任意

  return true
 end
 ###### 以上 ##############################################

 ######
 #
 # 次の新しい遷移値（次の基準点）の取得
 # - x: 現在時刻の値
 # - time: 現在時刻
 #
 ######
 def update_next_true_value x, time
  dist = @ave_models[time+1] - @ave_models[time]
  season_value = (average_train_power(t1) - solar_t1 + average_train_power(t1 + 1) \
                  - xmodel_t2) / 1.0 # 季節変動変数 
  @next_true_value =  @state_eq.call x, dist, season_value, Random::rand(-1.0..1.0) * @variance
 end

 ##
 # 学習データのある時刻の平均値を取得
 # - time: step数 15分刻みなら0-95
 # - return: 時刻timeにおけるN日分の平均値
 def average_train_power time
  ave = 0.0
  (0..@chunk_size).each{|i|
   ave += @trains[@weather][time + i * 1440 / TIMESTEP]
  }
  return (ave/@chunk_size)
 end

 ###
 # 平均的な天候モデルの初期化
 ###
 def init_ave_model
  root = File.expand_path File.dirname __FILE__
  @ave_models[SUNNY] = open("#{root}/../data/solar/nagoya/models/sunny.csv",'r').readline.split(',').map{|x| x.to_f}
  @ave_models[CLOUDY] = open("#{root}/../data/solar/nagoya/models/cloudy.csv",'r').readline.split(',').map{|x| x.to_f}
  @ave_models[RAINY] = open("#{root}/../data/solar/nagoya/models/rainy.csv",'r').readline.split(',').map{|x| x.to_f}
 end

 ###
 # 天候を設定する
 # - weather: 天候
 def set_weather weather
  @weather = weather
 end

 ###
 # 太陽光発電量から天気を判定する 
 # 
 #
 def eval_weather solar_power
  if solar_power > SUNNY_BORDER
   @weather = SUNNY
  elsif solar_power > CLOUDY_BORDER
   @weather = CLOUDY
  else
   @weather = RAINY
  end 
 end

end


