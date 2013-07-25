require 'pry'
require 'awesome_print'
require "#{File.expand_path File.dirname __FILE__}/../config/simulation_data"
#==============================================================
# Particle Filter
#
# 2013-07-25
# 季節変動を加味したパーティクルフィルタ
# 季節変動には天候別の過去N日のデータを参照して行う．
# 02との変更点:
#  - chunk_sizeの指定可能
#  - 状態方程式(季節変動が加味されたバージョン)
# 関連する論文:
#  現在作成中... 
#
# 参考URL: http://satomacoto.blogspot.jp/2012/11/python.html
# 
#===============================================================
class ParticleFilter
 attr_accessor :model_data,:trains,:config, :weather # for test
 include SimulationData

 def initialize config={}
  @config = {
   particles_number:2000,
   mean: 0.0,
   sigma: 1.0,
   model_data: [],
   weather: -1,
   timesteps: 96,
   chunk_size: 3
  }.merge(config)
  @rbm = RandomBoxMuller.new config={rand_number: @config[:particles_number]}
  @mean = @config[:mean]
  @sigma = @config[:sigma]
  @particles_number = @config[:particles_number]
  @current_ps = []
  #(1..@particles_number).each{|i|@current_ps << Random::rand(1.0) }
  @current_ps = (1..@particles_number).map{|a| @rbm.rnd_v 5.0, 1.0 }
  @pre_ps = []
  @current_pre = 0.0
  @pre_solars = []
  @model_data = @config[:model_data]
  @trains = {
    SUNNY => {data: [], timestamp: ""},
    CLOUDY => {data: [], timestamp: ""}, 
    RAINY => {data: [],  timestamp: ""},
    TEMP => {data: [], timestamp: ""}
  } # 学習データの保持(３日分)
  @sim_timesteps = @config[:timesteps]
  @weather = @config[:weather]
  #@current_pre = ps.inject(0){|sum,p| sum+=p}/@particles_number
  # 太陽光の電力
  @solars = []
 end

 # 実測値のデータをセットする
 def set_solar_data data
  @solars = data
 end

 # モデル曲線の設定
 def set_model_data data
  @model_data.clear
  @model_data = data
 end

 # 予測データの初期化,
 def init_data
  @pre_solars.clear
  @pre_ps = []
  @current_ps = (1..@particles_number).map{|a| @rbm.rnd_v 5.0, 1.0 }
  #@trains[TEMP][:data] = []
 end

 # 天候の初期化
 def set_weather weather
  @weather = weather
 end

 # x_t0： 一つ前のパーティクル値 (given
 # xmodel_t1：現在時刻のモデル値 (given
 # xmodel_t2：一つ先のモデル値 (given
 # x_pre： 一つ先の予測値 求める値
 # solar： 現在の実測値 (given
 # t1: 現在時刻
 # solar： 現在時刻の発電量
 def transition x_t1, t1, solar 
  w = @rbm.generate_rand_normval @mean, @sigma, 1
  xmodel_t1 = 0.0
  xmodel_t2 = 0.0
  if @model_data.size - 1 > t1 + 1
   xmodel_t1 = @model_data[t1]
   xmodel_t2 = @model_data[t1+1]
  else
   xmodel_t1 = @model_data[t1-1]
   xmodel_t2 = @model_data[t1]
  end
  ###
  if @pre_solars.size > 1 # 
   #ratio = (solar+1.0) / (@model_data[t1]+1.0)
   train = @trains[@weather][:data]
   # 次の状態:
   # 現在の実測値 + (現在の実測値 - 一つ前の予測値 + 一つ先の実測値 - 一つ前の実測値)/2.0
   # @current_pre: 現在時刻の実測値
   #xt_p2 = smooth_train t1 - 2 # ２つ前の時刻の平均
   #xt_p1 = smooth_train t1 - 1 # １つ前の時刻の平均
   #xt_crt = average_train_power t1
   x_t2 = t1 < @sim_timesteps - 1 ? xmodel_t2 : xmodel_t1
   #ap xm_t1
   x_pre = 0.0
   if train.size > 0
    #x_pre = @current_pre + ((solar * ratio - x_t0) + (xt_n1 - x_t0))/2.0 + w[0]
    #x_pre = @current_pre + (((solar - x_t0) + (xt_n1 - solar))/2.0 + (xt_n1 - x_t0))/2.0 + w[0]
    #x_pre = solar + (solar - @model_data[t1]) + ((solar - x_t0) + (xt_n1 - solar))/2.0 + w[0]
    delta = average_train_power(t1) - x_t1 + average_train_power(t1 + 1) - x_t2
    x_pre = solar + (xmodel_t2 - xmodel_t1) + delta + w[0] # Normal state transition formula
    #x_pre = @current_pre + (x_t0 - xt_n1) + w[0]
   else
    delta = average_train_power(t1) +  average_train_power(t1 + 1)
    x_pre = solar + xmodel_t2 - xmodel_t1 + w[0]
    #p "crnt_pre: #{@current_pre}, solar:#{solar}, x_t0: #{x_t0}, xm_t1: #{xm_t1}"
    #x_pre = @current_pre + (((solar - x_t0) + (xm_t1 - solar))/2.0 + (xm_t1 - x_t0))/2.0 + w[0]
    #x_pre = @current_pre + ((solar * ratio - x_t0.to_f) + (xm_t1 - x_t0))/2.0 + w[0]
   end
   return x_pre

  else # 初回の予測
   x_pre = @current_pre +  (xmodel_t1 * 1.2  - x_t1 * 1.0) +  w[0]
   return x_pre
  end
 end

 def observe x
  # 20.0w幅で観測(適当に設定)
  # TODO: 天候の実績値のデータからの観測
  pn = [0.0, 10.0, 20.0]
  #pn = [@current_pre - 10.0, @current_pre, @current_pre + 10.0]
  #pn = [@current_pre-10.0, @current_pre, @current_pre+10.0]
  # noise sigma = 3
  v = @rbm.generate_rand_normval 1.0, 3.0, 3
  #p x
  y = v.map.with_index{|m, i| x - pn[i] + v[i]}
  return y
 end

 def likehood y, x
  # DESCRIPTION: sigmaの値の定義はよくわからない
  sigma = 1.0
  tmp_ys = observe x
  dot = (y.map.with_index{|m,index| Math.sqrt (m - tmp_ys[index])**2}).inject(0){|sum,n| sum += n}
  return Math.exp(dot/sigma)
 end

 def importance_sampling w, x_pre, y
  w_update =  w * likehood( y, x_pre)
  return w_update
 end

 def resample xs, ws
  #print xs[0..10],"\n"
  x_resample = []
  rand_list = @rbm.generate_rand_norm 1.0, 3.0, @particles_number
  tmp_rand_sum = rand_list.inject(0.0){|sum,rd| sum+=rd}
  rand_list = rand_list.map{|m| m /= tmp_rand_sum}

  #rand_list = (1..@particles_number).map{|i| }
  # 重みにノイズ補正をかける
  tmp_ws = ws.map.with_index{|m,i| m * rand_list[i]}
  tmp_ws_sum = (tmp_ws.inject(0){|sum,ws| sum += ws})
  tmp_ws = tmp_ws.map{|w| w /=tmp_ws_sum}

  weight_samples = []
  # 重みの正規化
  tmp_particle_number = 0
  (tmp_ws).each do |m|
   number = (m * @particles_number)
   weight_samples << number
  end

  # リサンプルする
  begin
   weight_samples.each_with_index do |num, index|
    (1..num).each{|j| x_resample << xs[index] }
   end
  rescue
   #p tmp_rand_sum
  end

  w_resample = Array.new(xs.size,1.0)
  return [x_resample, w_resample]
 end

 # フィルタ分布用
 # グラフを作成するために用いる
 # 実行には ',' で区切られたデータが必要
 def exec_filter filename
  actuals = [] # 実測値
  actuals = (open(filename,'r').inject(""){|str,line|str + line.chomp}).join(',')
  ys = [] # 観測値
  x = 0.0 # 0から始まる
  # actuals.size はステップ数
  (0..actuals.size-1).each{|i| ys << self.observe(actuals[i]) }
  # 初期条件設定
  ps = []
  ws = []
  (1..@particles_number).each{|j|
   ps << Random::rand(0..20.0) * 30
   ws << 1.0
  }
  
  # パーティクルの位置と推定値の保存
  particles = [ps]
  predictions = [ps.inject(0){|sum,p| sum+=p} / @particles_number]

  # パーティクルフィルタ
  ys.each do |y| 
   ps, ws = pf_sir_step ps, ws, y
   particles << ps
   predictions << [ps.inject(0){|sum,p| sum+=p} / @particles_number]
  end
 end

 def pf_sir_step ps, ws, y
  n = ps.size # パーティクル数
  # 初期化
  x_predicted = Array.new(n)
  w_updated = Array.new(n)
  # 推定 prediction 
 end

 # 予測用
 # OneStep particle filter simple importance sampling!
 def pf_sir_one_step ps, ws, y, x_t0, time
  n = ps.size
  x_predicted = Array.new(n,0.0)
  w_updated = Array.new(n,1.0)
  # 推定 
  (0..n-1).each{|i|x_predicted[i] = self.transition ps[i], time, x_t0}

  # 更新
  (0..n-1).each{|i| w_updated[i] = self.importance_sampling(ws[i], x_predicted[i], y)}

  # リサンプリング
  xs_resampled, ws_resampled = self.resample x_predicted, w_updated
  return [xs_resampled, ws_resampled] 
 end

 # x_t0: 現在時刻の値
 # time: 現在時刻
 def next_value_predict x_t0, time
  x_t1 = self.transition @current_pre, time, x_t0
  #x_t1 = time > 0 ? self.transition(@pre_solars[time-1], time, x_t0) : self.transition( @current_pre, time, x_t0)
  y = self.observe x_t1
  ws = Array.new(@particles_number,1.0)
  @current_ps, ws = self.pf_sir_one_step @current_ps, ws, y, x_t0, time
  @current_pre = @current_ps.inject(0){|sum,p| sum+=p}/@particles_number
  result = @current_pre  
  @current_pre = x_t0 # 実測値に置き換える
  @pre_solars.push x_t0
  #@pre_solars.unshift @current_pre
  #@pre_solars.pop if @pre_solars.size > 5
  #@pre_ps.unshift @current_ps
  #@pre_ps.pop if @pre_ps.size > 3
  #print @current_ps.join(','),"\n"
  train_per_step x_t0 # 学習する

  return result < 0.0 ? 0.0 : result # 0以下は0にする
 end

 # Box=Muller法による正規乱数生成し確率を返す
 class RandomBoxMuller
  def initialize config={}
   @config = {
    mean: 0,
    sigma: 1.0,
    rand_number: 10
   }.merge(config)
   @mean = @config[:mean]
   @sigma = @config[:sigma]
   @rand_number = @config[:rand_number]
  end
  
  def generate_rand
   results = []
   # N回乱数生成を繰り返す
   0.upto(@rand_number - 1) do |num|
    results << rnd_v( @mean, @sigma)
   end
   return results
  end

  # パラメータを随時設定可能の奴
  # 確率密度を取得
  def generate_rand_norm mean, sigma, rand_number
   results = []
   # N回乱数生成を繰り返す
   0.upto(rand_number - 1) do |num|
    results << rnd_p(mean, sigma)
   end
   return results
  end
  
  # 正規乱数を取得
  def generate_rand_normval mean, sigma, rand_number
   results = []
   # N回乱数生成を繰り返す
   0.upto(rand_number - 1) do |num|
    results << rnd_v(mean, sigma)
   end
   return results
  end

  # 正規分布の確率をランダムで取得  
  def rnd_p mean, sigma
   r_1 = rand
   r_2 = rand
   x = Math.sqrt(sigma) * Math.sqrt(-2.0 * Math.log(r_1)) * Math.cos(2.0 * Math::PI * r_2) + mean
   #y = Math.sqrt(-2.0 * Math.log(r_1)) * Math.sin(2.0 * Math::PI * r_2) + @mean
   return gaussian x
  end

  # 正規分布の確率変数をランダムで取得
  def rnd_v mean, sigma 
   r_1 = rand
   r_2 = rand
   x = Math.sqrt(sigma) * Math.sqrt(-2.0 * Math.log(r_1)) * Math.cos(2.0 * Math::PI * r_2) + mean
   #y = Math.sqrt(-2.0 * Math.log(r_1)) * Math.sin(2.0 * Math::PI * r_2) + @mean
   return x
  end

  def gaussian x
   return Math.exp(-(x - @mean)**2/2.0*@sigma) / Math.sqrt(2.0*Math::PI*@sigma)
  end
 end

 private

 # 学習データから平滑化データの取得
 def get_smooth_data_from_trains type
  begin
   return @trains[type][:data].inject(0.0){|acc, data| acc += data  }
  rescue
   print "<<ERROR: TYPE CODE #{type} does not exist model.>>\n"
  end
 end

 # ある時刻での学習データからの予測値計算（３日分）
 def average_train_power time
  chunk_size = @config[:chunk_size] # 学習データのサイズ（日数）
  train = @trains[@weather][:data]
  train_size = train.size
   
  #ap train.size
  begin 
   # 学習データが最大スタックされているとき
   if train_size > @sim_timesteps * chunk_size - 1
    return (0..chunk_size-1).inject(0.0){|acc,i| acc += train[time+(i*@sim_timesteps)]}/(chunk_size.to_f)
   else # 学習データが最大スタックされてないとき
    result = 0.0
    cnt = 0.0
    for i in (0..chunk_size-1)
     break unless train_size > time + (@sim_timesteps*i)
     result += train[time + @sim_timesteps * i]
     cnt += 1
    end
    result /= cnt.to_f if cnt != 0
    return result
   end
  rescue => e
   #e.backtrace
   print "<<ERROR: #{time} does not exist model.>>\n"
   print e.backtrace
  end
 end
 
 # 学習する（毎時間Check）
 # data: 現在時刻のある曇の太陽光発電量
 # chunk_size: 学習する日数
 # train_size: 学習データのサイズ to check the chunk_size for updating trains 
 # tmp_train: 1回分の学習データ格納場所(1日毎に初期化)
 def train_per_step data
  chunk_size = @config[:chunk_size].nil? ? 3 : @config[:chunk_size] 
  train_size = @trains[@weather][:data].size # pointer
  tmp_train = @trains[TEMP][:data] # pointer

  @trains[TEMP][:data] << data
  if tmp_train.size == @sim_timesteps
   # N日分の学習データがすでにあるかどうか調べる
   if train_size < chunk_size * @sim_timesteps
    @trains[@weather][:data].concat @trains[TEMP][:data].clone # 結合
   else
    # ３日分の学習データが存在する場合
    @trains[@weather][:data].slice!(0,@sim_timesteps)
    @trains[@weather][:data].concat @trains[TEMP][:data].clone # 結合
   end
   #p "#{@trains[TEMP][:data].size} --- #{@trains[@weather][:data].size}"
   @trains[TEMP][:data] = [] # tmp_trainの削除
   #p "#{@trains[TEMP][:data].size} --- #{@trains[@weather][:data].size}"
  end
 end

end

