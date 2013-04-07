# 
# Particle Filter
#
class ParticleFilter

 def initialize config={}
  @config = {
   particles_number:2000,
   mean: 0.0,
   sigma: 1.0,
   model_data: []
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
 end

 # サンプル用
=begin
 def transition x_t0, t1
  w = @rbm.generate_rand_normval @mean, @sigma, 1
  # 実測値と現在値の変化量にノイズを乗せる
  varies = []
  if t1 > 3
   (t1-12..t1-1).each {|index|
    varies.unshift(@model_data[index+1] * 1.0 - @model_data[index]*1.0) if index > 0
   }
   #p varies if t1 == 5
   #@pre_solars.each_with_index{|x,index| varies.unshift(@pre_solars[index+1] - x) if @pre_solars.size > index+1}
   #delta = varies.sort[varies.size/2]
   delta = varies[1] - varies[0] + varies.inject(0.0){|x,sum| sum += x * 1.2}/varies.size
   alpha = varies.inject(0.0){|x,sum| sum += x * 1.2}/varies.size
   #p delta if t1 == 5
   x_pre = @current_pre + delta
   return x_pre
  elsif t1 > 2
   x_pre = @current_pre + @model_data[1] * 1.4 - @model_data[0] * 0.8 + w[0]
   return x_pre
  elsif t1 > 1
   x_pre = @current_pre + @model_data[0] + w[0]
   return x_pre
  else
   x_pre = @current_pre + w[0]
   #x_pre = @current_pre +  (x_t1 * 1.4  - x_t0 * 1.0) +  w[0]
   return x_pre 
  end
 end
=end 
 def transition x_t0, t1, solar
  w = @rbm.generate_rand_normval @mean, @sigma, 1
  x_t1 = @model_data.size - 1 > t1+1 ? @model_data[t1+1] : @model_data[t1]
  if @pre_solars.size > 1
   alpha = 0.0
   (1..@pre_solars.size-1).each{|index|
    alpha += (@pre_solars[index] - @pre_solars[index-1])
   }
   alpha = @pre_solars[t1-2]
   #p alpha if t1 == 8
   #p "#{alpha}:#{(x_t1 * 1.4 - x_t0 * 1.0)}" if t1 == 12
   x_pre = @current_pre + (solar - x_t0) + ((x_t1 * 1.2  - x_t0 * 1.0) + (x_t1 * 1.2 - alpha * 1.0) )/2.0+  w[0]
   return x_pre
  else
   x_pre = @current_pre +  (x_t1 * 1.2  - x_t0 * 1.0) +  w[0]
   return x_pre
  end
 end

 def observe x
  # 40.0kw幅で観測(適当に設定)
  pn = [0.0, 10.0, 20.0]
  #pn = [@current_pre - 10.0, @current_pre, @current_pre + 10.0]
  #pn = [@current_pre-10.0, @current_pre, @current_pre+10.0]
  # noise sigma = 3
  v = @rbm.generate_rand_normval 1.0, 3.0, 3
  #p x
  y = v.map.with_index{|m,i| x - pn[i] + v[i]}
  return y
 end

 def likehood y, x
  # sigma=3
  sigma = 3.0
  tmp_ys = observe x
  dot = (y.map.with_index{|m,index| Math.sqrt (m - tmp_ys[index])**2}).inject(0){|sum,n| sum += n}
  #dot = (y.map.with_index{|m,index| (m - tmp_ys[index])**2}).inject(0){|sum,n| sum += n}
  #y.map.with_index{|v,index| p (v - tmp_ys[index])**2; p v; p tmp_ys[index] }
  #p tmp_ys
  #p y
  #p x
  #dot = [x - pn[0],x - pn[1], x-pn[1] ].inject(0){|sum,l|sum += l*l }
  #p dot/sigma
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
  weight_samples.each_with_index do |num, index|
   (1..num).each{|j| x_resample << xs[index] }
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

 def next_value_predict x_t0, time
  x_t1 = self.transition @current_pre, time, x_t0
  y = self.observe x_t1
  ws = Array.new(@particles_number,1.0)
  @current_ps, ws = self.pf_sir_one_step @current_ps, ws, y, x_t0, time
  @current_pre = @current_ps.inject(0){|sum,p| sum+=p}/@particles_number
  
  @pre_solars.push x_t0
  #@pre_solars.unshift @current_pre
  #@pre_solars.pop if @pre_solars.size > 5
  #@pre_ps.unshift @current_ps
  #@pre_ps.pop if @pre_ps.size > 3

  #print @current_ps.join(','),"\n"
  return @current_pre < 0.0 ? 0.0 : @current_pre # 0以下は0にする
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
end

