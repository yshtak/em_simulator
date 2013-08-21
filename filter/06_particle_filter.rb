# coding: utf-8
require 'pry'
require 'awesome_print'
require "#{File.expand_path File.dirname __FILE__}/../config/simulation_data"
require "#{File.expand_path File.dirname __FILE__}/../lib/particle"
###################################################################
#
#=ParticleFilter
# 太陽光発電のパーティクルフィルタ（予測）
#
# 2013-07-26(途中)
# 2013-07-27(完成)
# 
# Usage:
#  predict_next_value(solar, time)
#   
#
##################################################################
class ParticleFilter
 include SimulationData
 include Particle
 PARTICLE_NUM=1000
 STEP=10

 attr_accessor :particles, :chunk_size, :ave_models, :weather, :trains

 def initialize cfg={}
  config = {
   chunk_size: 3,
   weather: SUNNY
  }.merge(cfg)

  @particles = Array.new(PARTICLE_NUM) # 粒子
  @particles.map!{|x| Particle.new}
  @chunk_size = config[:chunk_size] ## 学習日数
  @next_true_particle = Particle.new # 次の状態方程式に沿った値
  @ave_models = {} ## 平均的モデル
  @system_variance = 5.0 # 実験的に求める
  init_ave_model
  @rbm = RandomBoxMuller.new # Random生成器（正規乱数）

  @state_eq = ->(x, dist, season_value,rnd) { x + dist + season_value + rnd }

  @trains = { # 学習データ
   SUNNY => [],
   CLOUDY => [],
   RAINY => [],
   TEMP => []
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
  # 累積重みの計算
  weights = Array.new(@particles.size, 0.0)
  weights[0] = @particles[0].weight
  for index in 1..weights.size-1 do
   weights[index] = weights[index-1] + @particles[index].weight
  end 
  # 重みを基準にパーティクルをリサンプリングして重みを1.0に(エリート選択)
  tmp_particles = @particles.clone
  for index in 0..@particles.size-1 do
   w = @rbm.generate_rand_norm(0.0,1.0,1)[0] * weights[weights.size - 1] # Randを入れる(正規乱数に修正すること)
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
 def predict solar_t1, t1 
  xmodel_t2 = @ave_models[@weather][t1+1] # 時刻t1+1のモデルデータ
  xmodel_t1 = @ave_models[@weather][t1] # 時刻t1のモデルデータ
  if xmodel_t2.nil?
   xmodel_t2 = xmodel_t1
   xmodel_t1 = @ave_models[@weather][t1-1]
  end
  #season_value = (average_train_power(t1) - solar_t1 + average_train_power(t1 + 1) ) / 1.0 # 季節変動変数 
  #season_value = (average_train_power(t1) - solar_t1 + average_train_power(t1 + 1) - xmodel_t2) / 1.0 # 季節変動変数 
  season_value = (average_train_power(t1+1) - average_train_power(t1)) / 1.0 # 季節変動変数 
  #season_value = (average_train_power(t1) - @particles[i].value + average_train_power(t1+1) - xmodel_t2) / 2.0 # 季節変動変数 
  #season_value = @next
  #season_value = 0.0
  variance = 1.0 
  # 状態方程式を割り当てる
  for i in 0..@particles.size-1 do
   # 状態遷移
   #@particles[i].value = @next_true_particle.value + (xmodel_t2 - xmodel_t1) + season_value #+ @rbm.generate_rand_normval(0.0,1.0,1)[0]
   #@particles[i].value = @next_true_particle.value + (xmodel_t2 - xmodel_t1) + season_value + @rbm.generate_rand_normval(0.0,1.0,1)[0]
   #@particles[i].value = @next_true_particle.value + (average_train_power(t1+1) - average_train_power(t1)) + @rbm.generate_rand_normval(0.0,1.0,1)[0]
   #@particles[i].value = @next_true_particle.value + (xmodel_t2 - xmodel_t1 + (average_train_power(t1+1) - average_train_power(t1)))/2.0 + @rbm.generate_rand_normval(0.0,1.0,1)[0]
   #@particles[i].value = @next_true_particle.value + xmodel_t2 - xmodel_t1 + @rbm.generate_rand_normval(0.0,1.0,1)[0]
   
   #if @trains[@weather].size > 0
   # @particles[i].value = solar_t1 + season_value + @rbm.generate_rand_normval(0.0,1.0,1)[0] * variance
   #else
   # @particles[i].value = solar_t1 + xmodel_t2 - xmodel_t1 + @rbm.generate_rand_normval(0.0,1.0,1)[0] * variance
   #end

   @particles[i].value = @particles[i].value + (xmodel_t2 - xmodel_t1 + season_value)/2.0 + @rbm.generate_rand_normval(0.0,1.0,1)[0] * variance
   @particles[i].value = solar_t1 + (xmodel_t2 - xmodel_t1 + season_value)/2.0 + @rbm.generate_rand_normval(0.0,1.0,1)[0] * variance
   
   #@particles[i].value = @next_true_particle.value + ((xmodel_t2 - xmodel_t1) + season_value)/2.0 + @rbm.generate_rand_normval(0.0,1.0,1)[0]
   #@particles[i].value = @particles[i].value + (xmodel_t2 - xmodel_t1) + season_value + @rbm.generate_rand_normval(0.0,1.0,1)[0]
   #@particles[i].value = @particles[i].value + ((xmodel_t2 - xmodel_t1) + season_value)/2.0 + @rbm.generate_rand_normval(0.0,1.0,1)[0]
   #ap "Index[#{t1},#{@weather}]: model data:#{xmodel_t1}:ParticleValue:#{@particles[i].value}: Actual Data:#{solar_t1}"
  end
  #dump_particles t1
  return true 
 end

 #== 重み付け関数（尤度計算関数）
 # - particle: パーティクル
 # - return: 尤度
 def likelihood particle
  ## 平均的なモデル及び最近のデータのモデルを利用
  # 観測地点
  #obs = [20.0,0.0,-20.0]
  obs = [0.0] ## TODO: 天候で分ける
  sigma = 3.0
  v = @rbm.generate_rand_normval 0.0, 1.0, obs.size 
  sum = 0.0
  variance = 1.0 # 実験的に求める
  #mu = @particles.inject(0.0){|acc, x|acc+=x.value}/@particles.size
  obs.each_with_index do |point,index|
   y = particle.value - point + v[index] * variance
   #dist = Math.sqrt((@next_true_particle.value - particle.value)**2)
   #sum += 1.0 + 1.0/(Math.sqrt(2.0*Math::PI) * sigma) * Math.exp(-dist*dist/(2.0*sigma*sigma))
   #sum +=  (Math.exp(-(@next_true_particle.value - particle.value)/(2.0*sigma**2)))/(Math.sqrt(Math::PI * sigma**2))
   sum +=  (Math.exp(-(@next_true_particle.value - y)/(2.0*sigma**2)))/(Math.sqrt(Math::PI * sigma**2))
   #sum += 1.0 + 1.0/(Math.sqrt(2.0*Math::PI) * sigma) * Math.exp(-dist*dist/(2.0*sigma*sigma))
  end
  return sum/obs.size
 end

 #== 重みの決定づけ関数
 # - @particles: 重み 
 # - ws:
 # - return: bool 
 def weight 
  sum_weight = 0.0
  # 尤度に従いパーティクルの重みを決定する
  for i in 0..@particles.size-1 do
   @particles[i].weight = likelihood @particles[i]
   sum_weight += @particles[i].weight
  end
  # 重みの正規化
  for i in 0..@particles.size-1 do
   @particles[i].weight = (@particles[i].weight / sum_weight)
   #@particles[i].weight = (@particles[i].weight / sum_weight) * @particles.size
  end
  return true
 end

 #== 全パーティクルの重み付き平均を現状として観測する関数
 # - particles:
 # - result_particle: 結果 
 # - return: Bool
 def measure #result_particle
  value = 0.0
  weight = 0.0
  for i in 0..@particles.size-1 do
   value += @particles[i].value * @particles[i].weight
   weight += @particles[i].weight
  end
  #result_particle.value = value/weight 
  #result_particle.weight = 1.0 # 任意
  #ap "value:#{value}"
  #ap "weight:#{weight}"
  value = value / weight # 平均値が予測の値
  return value < 0.0 ? 0.0 : value
 end
 ###### 以上 ##############################################

 ###
 # 次の値を予測する関数
 # ワンステップ毎に行うメソッド
 #  - solar: 現在の太陽光発電の実測値
 #  - time: 現在の時刻
 ##
 def predict_next_value solar, time
  update_next_true_value solar, time
  self.resample
  self.predict(solar, time)
  #(0..1).each do 
   self.weight
   self.resample
  #end
  result = self.measure
  ###

  ###
  return result
 end

 ######
 #
 # 次の新しい遷移値（次の基準点）の取得
 # - x: 現在時刻の値
 # - time: 現在時刻
 #
 ######
 def update_next_true_value x, time
  xmodel_t1 = @ave_models[@weather][time]
  xmodel_t2 = @ave_models[@weather][time+1]
  dist = xmodel_t2.nil? ? xmodel_t1 - @ave_models[@weather][time-1] : xmodel_t2 - xmodel_t1
  season_value = (average_train_power(time+1)-average_train_power(time))/1.0
  #season_value = (average_train_power(time) - x + average_train_power(time + 1)
  #                - xmodel_t2) / 1.0 # 季節変動変数 
  @next_true_particle.value =  x + dist + @rbm.generate_rand_norm(0.0,1.0,1)[0] 
  #@next_true_particle.value =  x + dist + season_value + @rbm.generate_rand_norm(0.0,1.0,1)[0] 
 end

 ##
 # 学習データのある時刻の平均値を取得
 # - time: step数 15分刻みなら0-95
 # - return: 時刻timeにおけるN日分の平均値
 def average_train_power time
  ave = 0.0
  train = @trains[@weather] # pointer
  time = time - 1 if time == 1440/TIMESTEP # 範囲超え内容
  if train.size < (1440 / TIMESTEP) # 学習データがあるかどうか
   return @ave_models[@weather][time]
  elsif train.size == (1440 / TIMESTEP) * @chunk_size ## 最大に学習してる
   (0..@chunk_size-1).each{|i|
    ave += train[time + i * 1440 / TIMESTEP]
   }
   return (ave/@chunk_size)
  else
   now_chunk = train.size / (1440/TIMESTEP)
   (0..now_chunk-1).each{|i|
    ave += train[time + i * 1440 / TIMESTEP]
   }
   return (ave/now_chunk)
  end
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

 ##
 # パーティクルの初期化
 # 1日毎に行う 
 def particles_zero
  @particles.map!{|par| Particle.new(0.0,1.0)}
 end

 ###
 # 太陽光発電量から天気を判定する 
 # - solar_power: 総発電量
 # - return: Weather 
 #
 def eval_weather solar_power
  if solar_power > SUNNY_BORDER
   @weather = SUNNY
  elsif solar_power > CLOUDY_BORDER
   @weather = CLOUDY
  else
   @weather = RAINY
  end 
  result = @weather
  return result
 end

 ##
 # ワンステップごとの学習をする
 # - solar: 学習データ
 ###
 def train_per_step solar
  @trains[TEMP] << solar
  if @trains[TEMP].size == (1440 / TIMESTEP)
   @trains[@weather].concat @trains[TEMP].clone # 学習データの追加
   @trains[TEMP] = [] # 一時退避の初期化
   # 学習データがチャンクサイズを越えた場合
   if @trains[@weather].size >= (1440/TIMESTEP)*@chunk_size 
    @trains[@weather].slice!(0, 1440/TIMESTEP) # 古いデータ削除
   end
  end
 end

 ##
 # Debug用
 def dump_particles time
  @count = @count.nil? ?  0 : @count + 1 
  f = open("dump/particle_#{@count}.csv",'w')
  @particles.each{|particle|
   f.write "#{particle.value}\n"
  }
 end

end


